codeunit 50328 "eInvoice Auto Recovery"
{
    /// <summary>
    /// Automatically recovers missing submission data from LHDN by searching recent submissions
    /// NO MANUAL INPUT REQUIRED - fully automated discovery
    /// </summary>
    procedure AutoRecoverInvoiceFromLHDN(var SalesInvHeader: Record "Sales Invoice Header"; var RecoveryMessage: Text): Boolean
    var
        InvoiceNo: Code[20];
        PostingDate: Date;
        SearchFromDate: Date;
        SearchToDate: Date;
        FoundSubmissionUID: Text;
        FoundDocumentUUID: Text;
        FoundStatus: Text;
        SearchResults: Text;
    begin
        RecoveryMessage := '';
        InvoiceNo := SalesInvHeader."No.";
        PostingDate := SalesInvHeader."Posting Date";

        // Validate invoice
        if InvoiceNo = '' then begin
            RecoveryMessage := 'Error: Invalid invoice number';
            exit(false);
        end;

        // Check if already has data
        if (SalesInvHeader."eInvoice Submission UID" <> '') and
           (SalesInvHeader."eInvoice UUID" <> '') then begin
            RecoveryMessage := 'Invoice already has submission data. Use "Check eInvoice Status" to refresh.';
            exit(false);
        end;

        // Setup search date range (±7 days from posting date)
        SearchFromDate := CalcDate('<-7D>', PostingDate);
        SearchToDate := CalcDate('<+7D>', PostingDate);

        RecoveryMessage := StrSubstNo('Searching LHDN for invoice %1...\\' +
                                     'Date range: %2 to %3\\\\',
                                     InvoiceNo,
                                     SearchFromDate,
                                     SearchToDate);

        // Strategy: Search other invoices' submissions from the same date range
        if SearchViaOtherSubmissions(InvoiceNo, SearchFromDate, SearchToDate,
                                     FoundSubmissionUID, FoundDocumentUUID,
                                     FoundStatus, SearchResults) then begin
            // Found it! Update the invoice
            RecoveryMessage += SearchResults;
            exit(UpdateInvoiceWithRecoveredData(SalesInvHeader, FoundSubmissionUID,
                                                FoundDocumentUUID, FoundStatus,
                                                RecoveryMessage));
        end;

        // Not found
        RecoveryMessage += SearchResults + '\\\\Invoice not found in LHDN portal for the date range.\\' +
                          'Possible reasons:\\' +
                          '1. Invoice was submitted outside the search window\\' +
                          '2. Invoice number in BC does not match LHDN internalId\\' +
                          '3. Invoice was submitted to a different environment\\' +
                          '4. Invoice submission failed and was not accepted by LHDN';
        exit(false);
    end;

    /// <summary>
    /// Bulk recovery for multiple invoices - processes them in batch
    /// </summary>
    procedure BulkAutoRecoverInvoices(var SalesInvHeaderFilter: Record "Sales Invoice Header";
                                      var SuccessCount: Integer; var FailCount: Integer;
                                      var SkipCount: Integer; var RecoveryResults: Text)
    var
        SalesInvHeader: Record "Sales Invoice Header";
        Window: Dialog;
        ProcessingLbl: Label 'Processing invoice #1###### of #2######\\Current: #3##################\\Status: #4##################';
        Counter: Integer;
        TotalCount: Integer;
        CurrentInvoice: Text;
        CurrentStatus: Text;
        RecoveryMessage: Text;
        Success: Boolean;
    begin
        SuccessCount := 0;
        FailCount := 0;
        SkipCount := 0;
        RecoveryResults := '';
        Counter := 0;

        // Copy filters
        SalesInvHeader.CopyFilters(SalesInvHeaderFilter);
        TotalCount := SalesInvHeader.Count();

        if TotalCount = 0 then
            exit;

        // Open progress window
        Window.Open(ProcessingLbl);
        Window.Update(2, TotalCount);

        // Process each invoice
        if SalesInvHeader.FindSet(true) then
            repeat
                Counter += 1;
                CurrentInvoice := SalesInvHeader."No.";
                Window.Update(1, Counter);
                Window.Update(3, CurrentInvoice);
                Window.Update(4, 'Searching LHDN...');

                // Try to recover
                Clear(RecoveryMessage);
                Success := AutoRecoverInvoiceFromLHDN(SalesInvHeader, RecoveryMessage);

                if Success then begin
                    SuccessCount += 1;
                    CurrentStatus := 'SUCCESS';
                    RecoveryResults += StrSubstNo('✓ %1: Recovered (UID: %2)\\',
                                                 CurrentInvoice,
                                                 CopyStr(SalesInvHeader."eInvoice Submission UID", 1, 20));
                end else begin
                    // Check if it was skipped or failed
                    if RecoveryMessage.Contains('already has submission data') then begin
                        SkipCount += 1;
                        CurrentStatus := 'SKIPPED';
                    end else begin
                        FailCount += 1;
                        CurrentStatus := 'FAILED';
                        RecoveryResults += StrSubstNo('✗ %1: %2\\',
                                                     CurrentInvoice,
                                                     CopyStr(RecoveryMessage, 1, 80));
                    end;
                end;

                Window.Update(4, CurrentStatus);

                // Rate limiting to respect LHDN API limits (300 RPM)
                Sleep(300);

            until SalesInvHeader.Next() = 0;

        Window.Close();

        // Add summary to results
        RecoveryResults := StrSubstNo('Recovery Summary:\\' +
                                     '================\\' +
                                     'Total: %1\\' +
                                     'Success: %2\\' +
                                     'Failed: %3\\' +
                                     'Skipped: %4\\\\' +
                                     'Details:\\' +
                                     '%5',
                                     TotalCount, SuccessCount, FailCount, SkipCount, RecoveryResults);
    end;

    /// <summary>
    /// Search for invoice by querying other known submissions from the same period
    /// </summary>
    local procedure SearchViaOtherSubmissions(InvoiceNo: Code[20]; FromDate: Date; ToDate: Date;
                                              var FoundSubmissionUID: Text; var FoundDocumentUUID: Text;
                                              var FoundStatus: Text; var SearchResults: Text): Boolean
    var
        SubmissionLog: Record "eInvoice Submission Log";
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        eInvoiceHelper: Codeunit eInvoiceHelper;
        eInvoiceSetup: Record "eInvoiceSetup";
        RequestHeaders: HttpHeaders;
        AccessToken: Text;
        Url: Text;
        ResponseText: Text;
        FromDT: DateTime;
        ToDT: DateTime;
        CheckedCount: Integer;
        MaxToCheck: Integer;
    begin
        FoundSubmissionUID := '';
        FoundDocumentUUID := '';
        FoundStatus := '';
        CheckedCount := 0;
        MaxToCheck := 50; // Limit to avoid timeout

        // Build date range
        FromDT := CreateDateTime(FromDate, 000000T);
        ToDT := CreateDateTime(ToDate, 235959T);

        // Find other submissions from the same date range
        SubmissionLog.SetFilter("Submission UID", '<>%1', '');
        SubmissionLog.SetRange("Submission Date", FromDT, ToDT);
        SubmissionLog.SetFilter(Status, '%1|%2', 'Valid', 'Submitted'); // Check successful submissions

        SearchResults := StrSubstNo('Found %1 other submissions in date range\\', SubmissionLog.Count());

        if not SubmissionLog.FindSet() then begin
            SearchResults += 'No other submissions found for comparison\\';
            exit(false);
        end;

        // Get setup for API calls
        if not eInvoiceSetup.Get('SETUP') then begin
            SearchResults += 'Error: eInvoice Setup not found\\';
            exit(false);
        end;

        // Get access token
        eInvoiceHelper.InitializeHelper();
        AccessToken := eInvoiceHelper.GetAccessTokenFromSetup(eInvoiceSetup);
        if AccessToken = '' then begin
            SearchResults += 'Error: Failed to get access token\\';
            exit(false);
        end;

        // Search through each submission
        repeat
            CheckedCount += 1;
            SearchResults += StrSubstNo('Checking submission %1/%2: %3...',
                                       CheckedCount,
                                       MinValue(SubmissionLog.Count(), MaxToCheck),
                                       CopyStr(SubmissionLog."Submission UID", 1, 20));

            // Query LHDN for this submission
            if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
                Url := StrSubstNo('https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1',
                                 SubmissionLog."Submission UID")
            else
                Url := StrSubstNo('https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1',
                                 SubmissionLog."Submission UID");

            // Make API call
            Clear(HttpRequestMessage);
            Clear(HttpResponseMessage);
            HttpRequestMessage.Method('GET');
            HttpRequestMessage.SetRequestUri(Url);
            HttpRequestMessage.GetHeaders(RequestHeaders);
            RequestHeaders.Add('Authorization', StrSubstNo('Bearer %1', AccessToken));
            RequestHeaders.Add('Content-Type', 'application/json');
            RequestHeaders.Add('Accept', 'application/json');
            RequestHeaders.Add('Accept-Language', 'en');
            RequestHeaders.Add('User-Agent', 'BusinessCentral-eInvoice/2.0');

            if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) and
               HttpResponseMessage.IsSuccessStatusCode() then begin
                HttpResponseMessage.Content().ReadAs(ResponseText);

                // Search for our invoice in the documentSummary
                if FindInvoiceInSubmission(ResponseText, InvoiceNo, FoundDocumentUUID, FoundStatus) then begin
                    FoundSubmissionUID := SubmissionLog."Submission UID";
                    SearchResults += ' FOUND!\\';
                    exit(true);
                end else begin
                    SearchResults += ' not in this batch\\';
                end;
            end else begin
                SearchResults += ' API call failed\\';
            end;

            // Rate limiting
            Sleep(300);

        until (SubmissionLog.Next() = 0) or (CheckedCount >= MaxToCheck);

        SearchResults += StrSubstNo('\\Searched %1 submissions, invoice not found\\', CheckedCount);
        exit(false);
    end;

    /// <summary>
    /// Search for a specific invoice within a submission's documentSummary array
    /// </summary>
    local procedure FindInvoiceInSubmission(ResponseText: Text; InvoiceNo: Code[20];
                                           var DocumentUUID: Text; var Status: Text): Boolean
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummaryArray: JsonArray;
        DocumentObject: JsonObject;
        InternalId: Text;
        i: Integer;
    begin
        DocumentUUID := '';
        Status := '';

        // Parse response
        if not JsonObject.ReadFrom(ResponseText) then
            exit(false);

        // Get documentSummary array
        if not JsonObject.Get('documentSummary', JsonToken) or not JsonToken.IsArray() then
            exit(false);

        DocumentSummaryArray := JsonToken.AsArray();

        // Search each document
        for i := 0 to DocumentSummaryArray.Count() - 1 do begin
            DocumentSummaryArray.Get(i, JsonToken);
            if JsonToken.IsObject() then begin
                DocumentObject := JsonToken.AsObject();

                // Get internalId (this is the invoice number)
                if DocumentObject.Get('internalId', JsonToken) then begin
                    InternalId := CleanQuotesFromText(JsonToken.AsValue().AsText());

                    // Match invoice number
                    if InternalId = InvoiceNo then begin
                        // Found it! Extract UUID and status
                        if DocumentObject.Get('uuid', JsonToken) then
                            DocumentUUID := CleanQuotesFromText(JsonToken.AsValue().AsText());

                        if DocumentObject.Get('status', JsonToken) then
                            Status := CleanQuotesFromText(JsonToken.AsValue().AsText());

                        exit(true);
                    end;
                end;
            end;
        end;

        exit(false);
    end;

    /// <summary>
    /// Update invoice with recovered data and create submission log entry
    /// </summary>
    local procedure UpdateInvoiceWithRecoveredData(var SalesInvHeader: Record "Sales Invoice Header";
                                                   SubmissionUID: Text; DocumentUUID: Text;
                                                   Status: Text; var RecoveryMessage: Text): Boolean
    var
        SubmissionLog: Record "eInvoice Submission Log";
        Customer: Record Customer;
        SalesLine: Record "Sales Invoice Line";
        eInvoiceSetup: Record "eInvoiceSetup";
        TotalAmount: Decimal;
        TotalAmountInclVAT: Decimal;
    begin
        // Update invoice header
        SalesInvHeader."eInvoice Submission UID" := CopyStr(SubmissionUID, 1, MaxStrLen(SalesInvHeader."eInvoice Submission UID"));
        SalesInvHeader."eInvoice UUID" := CopyStr(DocumentUUID, 1, MaxStrLen(SalesInvHeader."eInvoice UUID"));
        SalesInvHeader."eInvoice Validation Status" := CopyStr(Status, 1, MaxStrLen(SalesInvHeader."eInvoice Validation Status"));

        if not SalesInvHeader.Modify(false) then begin
            RecoveryMessage += '\\Warning: Could not update invoice header (may be locked)\\';
        end;

        // Calculate amounts
        SalesLine.SetRange("Document No.", SalesInvHeader."No.");
        if SalesLine.FindSet() then
            repeat
                TotalAmount += SalesLine.Amount;
                TotalAmountInclVAT += SalesLine."Amount Including VAT";
            until SalesLine.Next() = 0;

        // Get customer
        if Customer.Get(SalesInvHeader."Sell-to Customer No.") then;

        // Create submission log entry
        SubmissionLog.Init();
        SubmissionLog."Entry No." := 0;
        SubmissionLog."Invoice No." := SalesInvHeader."No.";
        SubmissionLog."Customer No." := SalesInvHeader."Sell-to Customer No.";
        SubmissionLog."Customer Name" := Customer.Name;
        SubmissionLog."Amount" := TotalAmount;
        SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
        SubmissionLog."Submission UID" := SubmissionUID;
        SubmissionLog."Document UUID" := DocumentUUID;
        SubmissionLog.Status := Status;
        SubmissionLog."Submission Date" := CurrentDateTime; // Approximate
        SubmissionLog."Response Date" := CurrentDateTime;
        SubmissionLog."Last Updated" := CurrentDateTime;
        SubmissionLog."Posting Date" := SalesInvHeader."Posting Date";
        SubmissionLog."User ID" := UserId();
        SubmissionLog."Company Name" := CompanyName();
        SubmissionLog."Document Type" := SalesInvHeader."eInvoice Document Type";
        SubmissionLog."Error Message" := 'Auto-recovered from LHDN via date range scan';

        if eInvoiceSetup.Get('SETUP') then
            SubmissionLog.Environment := eInvoiceSetup.Environment;

        if not SubmissionLog.Insert(true) then begin
            RecoveryMessage += '\\Error: Could not create submission log entry\\';
            exit(false);
        end;

        RecoveryMessage += '\\Successfully recovered and saved all data!';
        exit(true);
    end;

    local procedure CleanQuotesFromText(InputText: Text): Text
    var
        CleanText: Text;
    begin
        CleanText := InputText;
        if StrPos(CleanText, '"') = 1 then
            CleanText := CopyStr(CleanText, 2);
        if StrLen(CleanText) > 0 then
            if CopyStr(CleanText, StrLen(CleanText), 1) = '"' then
                CleanText := CopyStr(CleanText, 1, StrLen(CleanText) - 1);
        exit(CleanText);
    end;

    local procedure MinValue(Value1: Integer; Value2: Integer): Integer
    begin
        if Value1 < Value2 then
            exit(Value1);
        exit(Value2);
    end;
}