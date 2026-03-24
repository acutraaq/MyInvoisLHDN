pageextension 50314 eInvPostedSalesCrMemoExt extends "Posted Sales Credit Memo"
{
    layout
    {
        addafter("Invoice Details")
        {
            group(eInvInfo)
            {
                Caption = 'e-Invoice';
                Visible = IsJotexCompany;
                field("eInvoice Document Type"; Rec."eInvoice Document Type")
                {
                    ApplicationArea = Suite;
                    ToolTip = 'Specifies the e-Invoice document type code';
                    Visible = IsJotexCompany;

                    trigger OnValidate()
                    var
                        Customer: Record Customer;
                        CustomerEInvoiceExt: Record "Customer";
                    begin
                        if not IsJotexCompany then
                            exit;

                        if Customer.Get(Rec."Sell-to Customer No.") then begin
                            // Safe way to check for the field
                            if CustomerEInvoiceExt.Get(Customer."No.") then
                                if (Rec."eInvoice Document Type" = '') and CustomerEInvoiceExt."Requires e-Invoice" then
                                    Error('e-Invoice Document Type must be specified for this customer.');
                        end;
                    end;
                }
                field("eInvoice Payment Mode"; Rec."eInvoice Payment Mode")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the Payment Mode';
                    Visible = IsJotexCompany;
                }
                field("eInvoice Currency Code"; Rec."eInvoice Currency Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the Currency Code';
                    Visible = IsJotexCompany;
                }
                field("eInvoice Version Code"; Rec."eInvoice Version Code")
                {
                    ApplicationArea = Suite;
                    ToolTip = 'Specifies version code for e-Invoice reporting';
                    Visible = IsJotexCompany;
                }
                field("eInvoice Submission UID"; Rec."eInvoice Submission UID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the LHDN Submission UID';
                    Visible = IsJotexCompany;
                    Editable = false;
                }
                field("KMAX eInvoice UUID"; Rec."eInvoice UUID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the LHDN Document UUID';
                    Visible = IsJotexCompany;
                    Editable = false;
                }
                field("eInvoice Validation Status"; Rec."eInvoice Validation Status")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the e-Invoice validation status from LHDN';
                    Visible = IsJotexCompany;
                    Editable = false;
                }
                field("eInv QR URL"; Rec."eInv QR URL")
                {
                    ApplicationArea = All;
                    Caption = 'Validation URL';
                    ToolTip = 'Public validation URL generated as {envbaseurl}/uuid-of-document/share/longid.';
                    Visible = IsJotexCompany;
                    ExtendedDatatype = URL;
                    Editable = false;
                }
                field("eInv QR Image"; Rec."eInv QR Image")
                {
                    ApplicationArea = All;
                    ShowCaption = false;
                    ToolTip = 'Displays the e-Invoice QR as an image when available.';
                    Visible = IsJotexCompany;
                    Editable = false;
                }
            }
        }
        addlast(FactBoxes)
        {
            part(eInvQrFactBox; "eInvoice QR CM FactBox")
            {
                ApplicationArea = All;
                Visible = IsJotexCompany;
                SubPageLink = "No." = FIELD("No.");
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            group(EInvoiceActions)
            {
                Caption = 'LHDN - MyInvois';
                Image = ElectronicDoc;
                ToolTip = 'e-Invoice actions for LHDN MyInvois';
                Visible = true; // Show this group so actions are visible

                action(GenerateQrImage)
                {
                    ApplicationArea = All;
                    Caption = 'Generate QR Image';
                    Image = Picture;
                    ToolTip = 'Generate and store the QR image from the validation URL.';
                    Visible = IsJotexCompany;
                    Enabled = eInvHasQrUrl;

                    trigger OnAction()
                    var
                        HttpClient: HttpClient;
                        Response: HttpResponseMessage;
                        QrServiceUrl: Text;
                        InS: InStream;
                        eInvoiceQrManager: Codeunit "eInvoice QR Manager";
                    begin
                        if Rec."eInv QR URL" = '' then begin
                            Message('No validation URL found.');
                            exit;
                        end;

                        // Prime validation URL
                        HttpClient.Get(Rec."eInv QR URL", Response);

                        // Render QR and store via codeunit (has modify permissions)
                        QrServiceUrl := StrSubstNo('https://quickchart.io/qr?text=%1&size=220', Rec."eInv QR URL");
                        if not HttpClient.Get(QrServiceUrl, Response) then begin
                            Message('Failed to connect to QR service.');
                            exit;
                        end;
                        if not Response.IsSuccessStatusCode then begin
                            Message('QR service error: %1 %2', Response.HttpStatusCode, Response.ReasonPhrase);
                            exit;
                        end;

                        Response.Content.ReadAs(InS);
                        if eInvoiceQrManager.UpdateCreditMemoQrImage(Rec."No.", InS, 'eInvoiceQR.png') then
                            CurrPage.Update(false)
                        else
                            Message('Failed to store QR image.');
                    end;
                }
                action(OpenValidationLink)
                {
                    ApplicationArea = All;
                    Caption = 'Open Validation Link';
                    Image = Web;
                    ToolTip = 'Open the public validation link in your browser.';
                    Visible = IsJotexCompany;
                    Enabled = eInvHasQrUrl;

                    trigger OnAction()
                    begin
                        if Rec."eInv QR URL" <> '' then
                            Hyperlink(Rec."eInv QR URL");
                    end;
                }
                action(RefreshStatus)
                {
                    ApplicationArea = All;
                    Caption = 'Refresh Status';
                    Image = Refresh;
                    ToolTip = 'Refresh the e-Invoice status from LHDN system using direct API call (same method as posted sales invoice)';
                    Visible = IsJotexCompany;

                    trigger OnAction()
                    var
                        HttpClient: HttpClient;
                        HttpRequestMessage: HttpRequestMessage;
                        HttpResponseMessage: HttpResponseMessage;
                        RequestHeaders: HttpHeaders;
                        AccessToken: Text;
                        eInvoiceSetup: Record "eInvoiceSetup";
                        eInvoiceHelper: Codeunit eInvoiceHelper;
                        ApiUrl: Text;
                        ResponseText: Text;
                        LongId: Text;
                        ValidationUrl: Text;
                        eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
                        eInvoiceQrManager: Codeunit "eInvoice QR Manager";
                    begin
                        if not IsJotexCompany then
                            exit;

                        if Rec."eInvoice Submission UID" = '' then begin
                            Message('No submission UID found for this credit memo.\Please submit the credit memo to LHDN first.');
                            exit;
                        end;

                        // Get setup for environment determination
                        if not eInvoiceSetup.Get('SETUP') then begin
                            Message('eInvoice Setup not found');
                            exit;
                        end;

                        // Get access token using the helper method (same as posted invoice)
                        eInvoiceHelper.InitializeHelper();
                        AccessToken := eInvoiceHelper.GetAccessTokenFromSetup(eInvoiceSetup);
                        if AccessToken = '' then begin
                            Message('Failed to get access token');
                            exit;
                        end;

                        // Build API URL same as posted invoice
                        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
                            ApiUrl := StrSubstNo('https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1', Rec."eInvoice Submission UID")
                        else
                            ApiUrl := StrSubstNo('https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1', Rec."eInvoice Submission UID");

                        // Setup request (same as posted invoice)
                        HttpRequestMessage.Method := 'GET';
                        HttpRequestMessage.SetRequestUri(ApiUrl);

                        // Set headers (same as posted invoice)
                        HttpRequestMessage.GetHeaders(RequestHeaders);
                        RequestHeaders.Clear();
                        RequestHeaders.Add('Accept', 'application/json');
                        RequestHeaders.Add('Accept-Language', 'en');
                        RequestHeaders.Add('Authorization', 'Bearer ' + AccessToken);

                        // Send request and use notifications like Posted Sales Invoice
                        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
                            HttpResponseMessage.Content.ReadAs(ResponseText);

                            if HttpResponseMessage.IsSuccessStatusCode then begin
                                // Parse the JSON response to extract the status
                                if UpdateCreditMemoStatusFromResponse(ResponseText) then begin
                                    // Try to update the credit memo field using the codeunit with proper permissions
                                    TryUpdateStatusViaCodeunit(ExtractStatusFromApiResponse(ResponseText));

                                    // Update validation URL when longId is available
                                    LongId := ExtractLongIdFromApiResponse(ResponseText, Rec."eInvoice UUID");
                                    if LongId <> '' then begin
                                        ValidationUrl := BuildValidationUrl(Rec."eInvoice UUID", LongId, eInvoiceSetup.Environment);
                                        if ValidationUrl <> '' then begin
                                            if eInvoiceQrManager.UpdateCreditMemoQrUrl(Rec."No.", ValidationUrl) then begin
                                                CurrPage.Update(false);

                                                // Automatically generate QR image after updating the URL
                                                AutoGenerateCreditMemoQrImage(Rec."No.", ValidationUrl);
                                            end;
                                        end;
                                    end;

                                    // Update cancel button state after status refresh
                                    CanCancelEInvoice := IsCancellationAllowed();

                                    SendStatusNotification(true, Rec."No.", ResponseText, Rec."eInvoice UUID");
                                end else begin
                                    SendStatusNotification(false, Rec."No.", 'Unable to parse LHDN response', '');
                                end;
                            end else begin
                                SendStatusNotification(false, Rec."No.", StrSubstNo('HTTP %1', HttpResponseMessage.HttpStatusCode), '');
                            end;
                        end else begin
                            SendStatusNotification(false, Rec."No.", 'Failed to connect to LHDN API', '');
                        end;
                    end;
                }
                action(SignAndSubmitToLHDN)
                {
                    ApplicationArea = All;
                    Caption = 'Sign & Submit to LHDN';
                    Image = ElectronicDoc;
                    Visible = IsJotexCompany;
                    ToolTip = 'Sign the credit memo via Azure Function and submit directly to LHDN MyInvois API';

                    trigger OnAction()
                    var
                        eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
                        LhdnResponse: Text;
                        Success: Boolean;
                        ErrorDetails: Text;
                    begin
                        // Suppress generator popups and show a non-blocking notification instead
                        eInvoiceGenerator.SetSuppressUserDialogs(true);
                        Success := eInvoiceGenerator.GetSignedCreditMemoAndSubmitToLHDN(Rec, LhdnResponse);

                        if Success then begin
                            SendSubmissionNotification(true, Rec."No.", LhdnResponse);
                            // Update the credit memo status to show successful submission
                            UpdateCreditMemoStatusFromResponse(LhdnResponse);
                        end else begin
                            // Enhanced error handling for failed submissions
                            ErrorDetails := ExtractLhdnErrorDetails(LhdnResponse);
                            SendSubmissionNotification(false, Rec."No.", ErrorDetails);

                            // Show detailed error message to user
                            ShowLhdnSubmissionError(ErrorDetails, LhdnResponse);

                            // Update the credit memo status to show failed submission
                            UpdateCreditMemoStatusFromResponse(LhdnResponse);
                        end;
                    end;
                }
                action(GenerateEInvoiceJSON)
                {
                    ApplicationArea = All;
                    Caption = 'Generate e-Invoice JSON';
                    Image = ExportFile;
                    ToolTip = 'Generate e-Invoice in JSON format for credit memo';
                    Visible = IsJotexCompany;

                    trigger OnAction()
                    var
                        eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
                        TempBlob: Codeunit "Temp Blob";
                        FileName: Text;
                        JsonText: Text;
                        OutStream: OutStream;
                        InStream: InStream;
                    begin
                        JsonText := eInvoiceGenerator.GenerateCreditMemoEInvoiceJson(Rec, false);

                        // Create download file
                        FileName := StrSubstNo('eInvoice_CreditMemo_%1_%2.json',
                            Rec."No.",
                            Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));

                        TempBlob.CreateOutStream(OutStream);
                        OutStream.WriteText(JsonText);
                        TempBlob.CreateInStream(InStream);
                        DownloadFromStream(InStream, 'Download e-Invoice JSON', '', 'JSON files (*.json)|*.json', FileName);
                    end;
                }



                action(CancelEInvoice)
                {
                    ApplicationArea = All;
                    Caption = 'Cancel e-Invoice';
                    Image = Cancel;
                    ToolTip = 'Cancel this e-Invoice in the LHDN MyInvois system';
                    Visible = IsJotexCompany;
                    Enabled = CanCancelEInvoice;

                    trigger OnAction()
                    var
                        eInvoiceCancellationHelper: Codeunit "eInvoice Cancellation Helper";
                        CancellationReason: Text;
                        SubmissionLog: Record "eInvoice Submission Log";
                        ConfirmMsg: Label 'Are you sure you want to cancel e-Invoice %1 in the LHDN system?\This action cannot be undone.';
                    begin
                        // Check if cancellation is allowed (should be disabled by Enabled property, but double-check)
                        if not IsCancellationAllowed() then begin
                            // Provide specific message based on current status
                            if Rec."eInvoice Validation Status" = 'Cancelled' then begin
                                Message('This e-Invoice has already been cancelled.\You cannot cancel an e-Invoice that is already cancelled.');
                                exit;
                            end;

                            SubmissionLog.SetRange("Invoice No.", Rec."No.");
                            if SubmissionLog.FindLast() and (SubmissionLog.Status = 'Cancelled') then begin
                                Message('This e-Invoice has already been cancelled.\Reason: %1\Cancelled on: %2',
                                        SubmissionLog."Cancellation Reason",
                                        Format(SubmissionLog."Cancellation Date"));
                                exit;
                            end;

                            if Rec."eInvoice Submission UID" = '' then begin
                                Message('This credit memo has not been submitted to LHDN.\Only submitted e-Invoices can be cancelled.');
                                exit;
                            end;

                            Message('This e-Invoice cannot be cancelled.\Only valid/accepted e-Invoices can be cancelled in the LHDN system.\Current status: %1',
                                    Rec."eInvoice Validation Status");
                            exit;
                        end;

                        // Verify that the credit memo has been submitted and is valid
                        SubmissionLog.SetRange("Invoice No.", Rec."No.");
                        SubmissionLog.SetRange(Status, 'Valid');
                        if not SubmissionLog.FindLast() then begin
                            Message('This credit memo has not been submitted to LHDN or is not in a valid state.\Only valid/accepted e-Invoices can be cancelled.');
                            exit;
                        end;

                        // Confirm cancellation
                        if not Confirm(ConfirmMsg, false, Rec."No.") then
                            exit;

                        // Get cancellation reason
                        CancellationReason := SelectCancellationReason();
                        if CancellationReason = '' then
                            exit;

                        // Proceed with cancellation (same pattern as posted sales invoice)
                        ClearLastError();
                        if eInvoiceCancellationHelper.CancelDocument(Rec."No.", CancellationReason) then begin
                            // Refresh the page to show updated status and disable cancel button
                            CanCancelEInvoice := IsCancellationAllowed();
                            CurrPage.Update(false);
                        end else begin
                            // Try alternative method with enhanced error handling
                            ClearLastError();
                            if eInvoiceCancellationHelper.CancelDocumentWithIsolation(Rec."No.", CancellationReason) then begin
                                Message('Cancellation completed using alternative method. Please refresh the submission log.');
                                CanCancelEInvoice := IsCancellationAllowed();
                                CurrPage.Update(false);
                            end else begin
                                // Show any error that occurred
                                if GetLastErrorText() <> '' then
                                    Message('Cancellation failed with error:\%1', GetLastErrorText())
                                else
                                    Message('Cancellation operation failed. Please check the submission log for details.');
                            end;
                        end;
                    end;
                }



                action(ShowSubmissionLogEntries)
                {
                    ApplicationArea = All;
                    Caption = 'Show Submission Log Entries';
                    Image = Log;
                    ToolTip = 'Show all submission log entries for this credit memo';
                    Visible = IsJotexCompany;

                    trigger OnAction()
                    var
                        SubmissionLog: Record "eInvoice Submission Log";
                        LogInfo: Text;
                        EntryCount: Integer;
                    begin
                        if not IsJotexCompany then
                            exit;

                        // Find all submission log entries for this credit memo
                        SubmissionLog.SetRange("Invoice No.", Rec."No.");
                        EntryCount := SubmissionLog.Count();

                        LogInfo := StrSubstNo('Submission Log Entries for Credit Memo %1:', Rec."No.");
                        LogInfo += '\';

                        if EntryCount = 0 then
                            LogInfo += 'No submission log entries found.'
                        else begin
                            if SubmissionLog.FindSet() then begin
                                repeat
                                    LogInfo += StrSubstNo('\Entry %1:', SubmissionLog."Entry No.");
                                    LogInfo += StrSubstNo('  Document Type: %1', SubmissionLog."Document Type");
                                    LogInfo += StrSubstNo('  Status: %1', SubmissionLog.Status);
                                    LogInfo += StrSubstNo('  Submission UID: %1', SubmissionLog."Submission UID");
                                    LogInfo += StrSubstNo('  Document UUID: %1', SubmissionLog."Document UUID");
                                    LogInfo += StrSubstNo('  Submission Date: %1', Format(SubmissionLog."Submission Date"));
                                    LogInfo += StrSubstNo('  Last Updated: %1', Format(SubmissionLog."Last Updated"));
                                    LogInfo += '\';
                                until SubmissionLog.Next() = 0;
                            end;
                        end;

                        if EntryCount = 0 then
                            LogInfo += '\This credit memo may not have been submitted to LHDN yet.'
                        else
                            LogInfo += StrSubstNo('\Total entries found: %1', EntryCount);

                        Message(LogInfo);
                    end;
                }
                action(ViewSubmissionLog)
                {
                    ApplicationArea = All;
                    Caption = 'View Submission Log';
                    Image = Log;
                    ToolTip = 'View submission log entries for this credit memo';
                    Visible = IsJotexCompany;

                    trigger OnAction()
                    var
                        SubmissionLog: Record "eInvoice Submission Log";
                        SubmissionLogPage: Page "e-Invoice Submission Log";
                    begin
                        SubmissionLog.SetRange("Invoice No.", Rec."No.");
                        if Rec."eInvoice Submission UID" <> '' then
                            SubmissionLog.SetRange("Submission UID", Rec."eInvoice Submission UID");

                        SubmissionLogPage.SetTableView(SubmissionLog);
                        SubmissionLogPage.RunModal();
                    end;
                }
            }
        }


    }

    // e-Invoice category group moved to promoted categories to avoid processing-area actionref errors

    var
        IsJotexCompany: Boolean;
        CanCancelEInvoice: Boolean;
        eInvHasQrUrl: Boolean;

    trigger OnOpenPage()
    var
        CompanyInfo: Record "Company Information";
    begin
        IsJotexCompany := CompanyInfo.Get() and (CompanyInfo.Name = 'JOTEX SDN BHD');
        CanCancelEInvoice := IsCancellationAllowed();
        eInvHasQrUrl := Rec."eInv QR URL" <> '';
    end;

    trigger OnAfterGetCurrRecord()
    begin
        CanCancelEInvoice := IsCancellationAllowed();
        eInvHasQrUrl := Rec."eInv QR URL" <> '';
    end;

    /// <summary>
    /// Enhanced submission notification with detailed error information
    /// Also updates submission log with error details for failed submissions
    /// </summary>
    /// <param name="Success">Whether submission was successful</param>
    /// <param name="DocNo">Document number</param>
    /// <param name="LhdnResponse">LHDN API response</param>
    local procedure SendSubmissionNotification(Success: Boolean; DocNo: Code[20]; LhdnResponse: Text)
    var
        Notif: Notification;
        Msg: Text;
        ErrorDetails: Text;
        SubmissionLog: Record "eInvoice Submission Log";
        Customer: Record Customer;
        CustomerName: Text[100];
    begin
        // Get customer name for the submission log
        CustomerName := '';
        if Customer.Get(Rec."Sell-to Customer No.") then
            CustomerName := Customer.Name;

        if Success then begin
            Msg := StrSubstNo('LHDN submission successful for Credit Memo %1. %2', DocNo, FormatLhdnResponseInline(LhdnResponse));

            // Update submission log with success status
            UpdateSubmissionLogWithResponse(DocNo, 'Submitted', LhdnResponse, CustomerName, '');
        end else begin
            // Extract detailed error information for failed submissions
            ErrorDetails := ExtractLhdnErrorDetails(LhdnResponse);
            Msg := StrSubstNo('LHDN submission failed for Credit Memo %1.\\%2', DocNo, ErrorDetails);

            // Update submission log with failure status and detailed error information
            UpdateSubmissionLogWithResponse(DocNo, 'Submission Failed', LhdnResponse, CustomerName, ErrorDetails);
        end;

        Notif.Scope := NotificationScope::LocalScope;
        Notif.Message(Msg);
        Notif.Send();
    end;

    local procedure FormatLhdnResponseInline(RawResponse: Text): Text
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        AcceptedArray: JsonArray;
        DocumentJson: JsonObject;
        SubmissionUid: Text;
        AcceptedCount: Integer;
        InvoiceCodeNumber: Text;
        Uuid: Text;
        Summary: Text;
    begin
        if not ResponseJson.ReadFrom(RawResponse) then
            exit(StrSubstNo('Raw Response: %1', CopyStr(RawResponse, 1, 200)));

        if ResponseJson.Get('submissionUid', JsonToken) then
            SubmissionUid := CleanQuotesFromText(SafeJsonValueToText(JsonToken));

        if ResponseJson.Get('acceptedDocuments', JsonToken) and JsonToken.IsArray() then begin
            AcceptedArray := JsonToken.AsArray();
            AcceptedCount := AcceptedArray.Count();
            if AcceptedCount > 0 then begin
                AcceptedArray.Get(0, JsonToken);
                if JsonToken.IsObject() then begin
                    DocumentJson := JsonToken.AsObject();
                    if DocumentJson.Get('invoiceCodeNumber', JsonToken) then
                        InvoiceCodeNumber := CleanQuotesFromText(SafeJsonValueToText(JsonToken));
                    if DocumentJson.Get('uuid', JsonToken) then
                        Uuid := CleanQuotesFromText(SafeJsonValueToText(JsonToken));
                end;
            end;
        end;

        Summary := StrSubstNo('Submission ID: %1 | Accepted Documents: %2', SubmissionUid, Format(AcceptedCount));
        if InvoiceCodeNumber <> '' then
            Summary += StrSubstNo(' | Credit Memo: %1', InvoiceCodeNumber);
        if Uuid <> '' then
            Summary += StrSubstNo(' | UUID: %1', Uuid);

        exit(Summary);
    end;

    local procedure SendStatusNotification(Success: Boolean; DocNo: Code[20]; RawResponseOrMessage: Text; CurrentUuid: Text)
    var
        Notif: Notification;
        Msg: Text;
        Inline: Text;
    begin
        if Success then begin
            Inline := FormatLhdnStatusInline(RawResponseOrMessage, CurrentUuid);
            Msg := StrSubstNo('LHDN status refreshed for Credit Memo %1. %2', DocNo, Inline);
        end else begin
            Msg := StrSubstNo('LHDN status refresh failed for Credit Memo %1. %2', DocNo, CopyStr(RawResponseOrMessage, 1, 250));
        end;

        Notif.Scope := NotificationScope::LocalScope;
        Notif.Message(Msg);
        Notif.Send();
    end;

    local procedure FormatLhdnStatusInline(RawResponse: Text; CurrentUuid: Text): Text
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        SubmissionUid: Text;
        DocSummary: JsonArray;
        DocObj: JsonObject;
        i: Integer;
        DocumentStatus: Text;
        PickedUuid: Text;
        Summary: Text;
    begin
        if not ResponseJson.ReadFrom(RawResponse) then
            exit(StrSubstNo('Raw Response: %1', CopyStr(RawResponse, 1, 200)));

        if ResponseJson.Get('submissionUid', JsonToken) then
            SubmissionUid := CleanQuotesFromText(JsonToken.AsValue().AsText());

        // Prefer document-level status that matches our UUID
        if ResponseJson.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocSummary := JsonToken.AsArray();
            for i := 0 to DocSummary.Count() - 1 do begin
                DocSummary.Get(i, JsonToken);
                if JsonToken.IsObject() then begin
                    DocObj := JsonToken.AsObject();
                    if DocObj.Get('uuid', JsonToken) then
                        PickedUuid := CleanQuotesFromText(JsonToken.AsValue().AsText());
                    if (CurrentUuid <> '') and (PickedUuid <> '') and (PickedUuid = CurrentUuid) then begin
                        if DocObj.Get('status', JsonToken) then
                            DocumentStatus := CleanQuotesFromText(JsonToken.AsValue().AsText());
                        break;
                    end;
                end;
            end;
        end;

        // Fallback to overallStatus if doc-level not found
        if (DocumentStatus = '') and ResponseJson.Get('overallStatus', JsonToken) then
            DocumentStatus := CleanQuotesFromText(JsonToken.AsValue().AsText());

        // Normalize casing
        case DocumentStatus.ToLower() of
            'valid':
                DocumentStatus := 'Valid';
            'invalid':
                DocumentStatus := 'Invalid';
            'in progress':
                DocumentStatus := 'In Progress';
            'partially valid':
                DocumentStatus := 'Partially Valid';
            'cancelled':
                DocumentStatus := 'Cancelled';
            'rejected':
                DocumentStatus := 'Rejected';
        end;

        Summary := StrSubstNo('Submission ID: %1 | Status: %2', SubmissionUid, DocumentStatus);
        if (PickedUuid <> '') then
            Summary += StrSubstNo(' | UUID: %1', PickedUuid)
        else if (CurrentUuid <> '') then
            Summary += StrSubstNo(' | UUID: %1', CurrentUuid);

        exit(Summary);
    end;

    /// <summary>
    /// Check if cancellation is allowed for this credit memo
    /// Returns false if the credit memo is already cancelled or not in a cancellable state
    /// </summary>
    /// <returns>True if cancellation is allowed, false otherwise</returns>
    local procedure IsCancellationAllowed(): Boolean
    var
        SubmissionLog: Record "eInvoice Submission Log";
    begin
        // Check if credit memo has validation status of "Cancelled"
        if Rec."eInvoice Validation Status" = 'Cancelled' then
            exit(false);

        // Check submission log for cancelled status
        SubmissionLog.SetRange("Invoice No.", Rec."No.");
        if SubmissionLog.FindLast() then begin
            if SubmissionLog.Status = 'Cancelled' then
                exit(false);
        end;

        // Check if credit memo has been submitted to LHDN (has submission UID)
        if Rec."eInvoice Submission UID" = '' then
            exit(false);

        // Additional check: Only allow cancellation if status is Valid
        // since only valid e-Invoices can be cancelled in LHDN
        if Rec."eInvoice Validation Status" <> 'Valid' then begin
            // Double-check with submission log
            SubmissionLog.SetRange("Invoice No.", Rec."No.");
            SubmissionLog.SetRange(Status, 'Valid');
            if not SubmissionLog.FindLast() then
                exit(false);
        end;

        exit(true);
    end;

    /// <summary>
    /// Select cancellation reason from predefined options or custom input
    /// </summary>
    /// <returns>Selected cancellation reason or empty string if cancelled</returns>
    local procedure SelectCancellationReason(): Text
    var
        Selection: Integer;
        CustomReason: Text[500];
        ReasonText: Text;
    begin
        ReasonText := '';

        // Show options dialog with custom input option
        Selection := StrMenu('Wrong buyer,Wrong invoice details,Duplicate invoice,Technical error,Buyer cancellation request,Other business reason,Enter custom reason', 1, 'Select cancellation reason:');

        case Selection of
            1:
                ReasonText := 'Wrong buyer information';
            2:
                ReasonText := 'Incorrect invoice details';
            3:
                ReasonText := 'Duplicate invoice submission';
            4:
                ReasonText := 'Technical error during submission';
            5:
                ReasonText := 'Cancellation requested by buyer';
            6:
                ReasonText := 'Other business reason - Contact support for details';
            7:
                begin
                    // Get custom reason input from user
                    CustomReason := GetCustomCancellationReason();
                    if CustomReason <> '' then
                        ReasonText := CustomReason
                    else
                        ReasonText := ''; // User cancelled
                end;
            else
                ReasonText := '';
        end;

        exit(ReasonText);
    end;

    /// <summary>
    /// Get custom cancellation reason from user input
    /// </summary>
    /// <returns>Custom reason text or empty string if cancelled</returns>
    local procedure GetCustomCancellationReason(): Text[500]
    var
        CustomReasonPage: Page 50317;
        CustomReason: Text[500];
    begin
        // Open the custom reason input page
        if CustomReasonPage.RunModal() = Action::OK then begin
            CustomReason := CustomReasonPage.GetCancellationReason();

            // Validate the reason is not empty
            if CustomReason <> '' then
                exit(CustomReason);
        end;

        // Return empty string if cancelled or no reason provided
        exit('');
    end;

    /// <summary>
    /// Parse LHDN API response and update credit memo status
    /// </summary>
    /// <param name="ResponseText">JSON response from LHDN API</param>
    /// <returns>True if status was updated successfully</returns>
    local procedure UpdateCreditMemoStatusFromResponse(ResponseText: Text): Boolean
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummaryArray: JsonArray;
        DocumentJson: JsonObject;
        DocumentUuid: Text;
        DocumentStatus: Text;
        OverallStatus: Text;
        LhdnStatus: Text;
        i: Integer;
    begin
        if not JsonObject.ReadFrom(ResponseText) then begin
            Message('Failed to parse LHDN API response.');
            exit(false);
        end;

        // Extract overall status first
        if JsonObject.Get('status', JsonToken) then
            OverallStatus := CleanQuotesFromText(JsonToken.AsValue().AsText());

        // Check document-level status for accurate cancellation detection
        if JsonObject.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocumentSummaryArray := JsonToken.AsArray();

            // Look for our specific document by UUID match
            for i := 0 to DocumentSummaryArray.Count() - 1 do begin
                DocumentSummaryArray.Get(i, JsonToken);
                if JsonToken.IsObject() then begin
                    DocumentJson := JsonToken.AsObject();

                    // Get document UUID and status
                    if DocumentJson.Get('uuid', JsonToken) then
                        DocumentUuid := CleanQuotesFromText(JsonToken.AsValue().AsText());

                    // If this is our document (UUID match), use its individual status
                    if (DocumentUuid = Rec."eInvoice UUID") and DocumentJson.Get('status', JsonToken) then begin
                        DocumentStatus := CleanQuotesFromText(JsonToken.AsValue().AsText());

                        // Convert document-level LHDN status values to proper case for display
                        case DocumentStatus.ToLower() of
                            'cancelled':
                                LhdnStatus := 'Cancelled';
                            'valid':
                                LhdnStatus := 'Valid';
                            'invalid':
                                LhdnStatus := 'Invalid';
                            'rejected':
                                LhdnStatus := 'Rejected';
                            else
                                LhdnStatus := DocumentStatus; // Use document status as-is
                        end;
                    end;
                end;
            end;
        end;

        // Fall back to overall status if no document-specific status found
        if LhdnStatus = '' then begin
            case OverallStatus.ToLower() of
                'valid':
                    LhdnStatus := 'Valid';
                'invalid':
                    LhdnStatus := 'Invalid';
                'in progress':
                    LhdnStatus := 'In Progress';
                'partially valid':
                    LhdnStatus := 'Partially Valid';
                else
                    LhdnStatus := OverallStatus; // Use as-is if unknown
            end;
        end;

        // Try to update the credit memo validation status field using the codeunit approach
        // This bypasses permission restrictions like the posted sales invoice does
        TryUpdateStatusViaCodeunit(LhdnStatus);

        // Always try to update the submission log
        UpdateCreditMemoSubmissionLogStatus(LhdnStatus);

        // Refresh the page to show the updated status
        CurrPage.Update(false);

        // Return true even if update failed due to permissions - the status check itself was successful
        exit(true);
    end;

    local procedure ExtractLongIdFromApiResponse(ResponseText: Text; DocumentUuid: Text): Text
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummary: JsonArray;
        Doc: JsonObject;
        PickedUuid: Text;
        i: Integer;
    begin
        if not JsonObject.ReadFrom(ResponseText) then
            exit('');

        if JsonObject.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocumentSummary := JsonToken.AsArray();
            for i := 0 to DocumentSummary.Count() - 1 do begin
                DocumentSummary.Get(i, JsonToken);
                if JsonToken.IsObject() then begin
                    Doc := JsonToken.AsObject();
                    PickedUuid := '';
                    if Doc.Get('uuid', JsonToken) then
                        PickedUuid := JsonToken.AsValue().AsText();
                    if (DocumentUuid = '') or (PickedUuid = DocumentUuid) then begin
                        if Doc.Get('longId', JsonToken) then
                            exit(JsonToken.AsValue().AsText());
                    end;
                end;
            end;
        end;
        exit('');
    end;

    local procedure BuildValidationUrl(DocumentUuid: Text; LongId: Text; Environment: Option Preprod,Production): Text
    var
        BaseUrl: Text;
    begin
        if (DocumentUuid = '') or (LongId = '') then
            exit('');

        if Environment = Environment::Preprod then
            BaseUrl := 'https://preprod.myinvois.hasil.gov.my'
        else
            BaseUrl := 'https://myinvois.hasil.gov.my';

        exit(StrSubstNo('%1/%2/share/%3', BaseUrl, DocumentUuid, LongId));
    end;

    /// <summary>
    /// Try to update credit memo status using the JSON Generator codeunit which has modify permissions
    /// This bypasses the permission restrictions on the page extension
    /// </summary>
    /// <param name="NewStatus">The new status to set</param>
    local procedure TryUpdateStatusViaCodeunit(NewStatus: Text)
    var
        eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
    begin
        // Use the JSON Generator codeunit which has tabledata "Sales Cr.Memo Header" = M permission
        if eInvoiceGenerator.UpdateCreditMemoValidationStatus(Rec."No.", NewStatus) then begin
            // Synchronize the Submission Log status
            SynchronizeCreditMemoSubmissionLogStatus(Rec."No.", NewStatus);

            // Refresh the current record to show updated status
            Rec.Get(Rec."No.");
            CurrPage.Update(false);
        end;
    end;

    /// <summary>
    /// Try to update credit memo status with proper error handling for permission restrictions
    /// </summary>
    /// <param name="NewStatus">The new status to set</param>
    /// <returns>True if successfully updated, false if permission denied</returns>
    [TryFunction]
    local procedure TryUpdateCreditMemoStatus(NewStatus: Text)
    begin
        // Attempt to update the status field
        Rec."eInvoice Validation Status" := NewStatus;

        // Try to save the changes - will fail gracefully if no modify permissions
        Rec.Modify();
    end;

    /// <summary>
    /// Update submission log status for this credit memo
    /// </summary>
    local procedure UpdateCreditMemoSubmissionLogStatus(NewStatus: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
    begin
        // Find the latest submission log entry for this credit memo
        SubmissionLog.SetRange("Invoice No.", Rec."No.");
        SubmissionLog.SetRange("Document Type", '02'); // Credit Memo
        if SubmissionLog.FindLast() then begin
            SubmissionLog.Status := NewStatus;
            SubmissionLog."Last Updated" := CurrentDateTime;
            if SubmissionLog.Modify(true) then; // Ignore errors for submission log updates
        end;
    end;

    /// <summary>
    /// Synchronize submission log status for credit memo using the codeunit approach
    /// </summary>
    /// <param name="CreditMemoNo">Credit memo number</param>
    /// <param name="NewStatus">New status to set</param>
    local procedure SynchronizeCreditMemoSubmissionLogStatus(CreditMemoNo: Code[20]; NewStatus: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
        Customer: Record Customer;
        CustomerName: Text[100];
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        // Get customer name from the credit memo
        CustomerName := '';
        if SalesCrMemoHeader.Get(CreditMemoNo) then
            if Customer.Get(SalesCrMemoHeader."Sell-to Customer No.") then
                CustomerName := Customer.Name;

        // Try to find existing log entry for this credit memo and submission UID
        SubmissionLog.SetRange("Invoice No.", CreditMemoNo);
        if SalesCrMemoHeader."eInvoice Submission UID" <> '' then
            SubmissionLog.SetRange("Submission UID", SalesCrMemoHeader."eInvoice Submission UID");

        if SubmissionLog.FindLast() then begin
            // Update existing log entry
            SubmissionLog.Status := NewStatus;
            SubmissionLog."Last Updated" := CurrentDateTime;
            SubmissionLog."Customer Name" := CustomerName;
            SubmissionLog."Error Message" := StrSubstNo('Status updated via API check: %1', NewStatus);
            if SubmissionLog.Modify() then begin
                // Successfully updated log
            end;
        end else begin
            // Create new log entry if none exists
            SubmissionLog.Init();
            SubmissionLog."Invoice No." := CreditMemoNo;
            SubmissionLog."Customer No." := SalesCrMemoHeader."Sell-to Customer No.";
            SubmissionLog."Amount" := SalesCrMemoHeader.Amount;
            SubmissionLog."Amount Including VAT" := SalesCrMemoHeader."Amount Including VAT";
            SubmissionLog."Submission UID" := SalesCrMemoHeader."eInvoice Submission UID";
            SubmissionLog."Document UUID" := SalesCrMemoHeader."eInvoice UUID";
            SubmissionLog.Status := NewStatus;
            SubmissionLog."Customer Name" := CustomerName;
            SubmissionLog."Submission Date" := CurrentDateTime;
            SubmissionLog."Last Updated" := CurrentDateTime;
            SubmissionLog."Error Message" := StrSubstNo('Status retrieved via API check: %1', NewStatus);
            SubmissionLog."Document Type" := SalesCrMemoHeader."eInvoice Document Type";
            if SubmissionLog.Insert() then begin
                // Successfully created log entry
            end;
        end;
    end;

    /// <summary>
    /// Removes surrounding quotes from text values
    /// </summary>
    /// <param name="InputText">Text that may contain surrounding quotes</param>
    /// <returns>Text with quotes removed</returns>
    local procedure CleanQuotesFromText(InputText: Text): Text
    var
        CleanText: Text;
    begin
        if InputText = '' then
            exit('');

        CleanText := InputText;

        // Remove leading quote if present
        if StrPos(CleanText, '"') = 1 then
            CleanText := CopyStr(CleanText, 2);

        // Remove trailing quote if present
        if StrLen(CleanText) > 0 then
            if CopyStr(CleanText, StrLen(CleanText), 1) = '"' then
                CleanText := CopyStr(CleanText, 1, StrLen(CleanText) - 1);

        exit(CleanText);
    end;

    /// <summary>
    /// Formats LHDN response JSON into a clean, readable format
    /// </summary>
    /// <param name="RawResponse">Raw JSON response from LHDN</param>
    /// <returns>Formatted response text</returns>
    local procedure FormatLhdnResponse(RawResponse: Text): Text
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        AcceptedArray: JsonArray;
        RejectedArray: JsonArray;
        SubmissionUid: Text;
        AcceptedCount: Integer;
        RejectedCount: Integer;
        i: Integer;
        DocumentJson: JsonObject;
        Uuid: Text;
        InvoiceCodeNumber: Text;
        FormattedResponse: Text;
    begin
        // Try to parse the JSON response
        if not ResponseJson.ReadFrom(RawResponse) then begin
            // If parsing fails, return a simplified version of the raw response
            exit('Raw Response: ' + CopyStr(RawResponse, 1, 200) + '...');
        end;

        // Extract submission UID
        if ResponseJson.Get('submissionUid', JsonToken) then
            SubmissionUid := CleanQuotesFromText(SafeJsonValueToText(JsonToken));

        // Extract accepted documents
        if ResponseJson.Get('acceptedDocuments', JsonToken) and JsonToken.IsArray() then begin
            AcceptedArray := JsonToken.AsArray();
            AcceptedCount := AcceptedArray.Count();

            if AcceptedCount > 0 then begin
                FormattedResponse := 'Submission ID: ' + SubmissionUid + '\\' +
                                   'Accepted Documents: ' + Format(AcceptedCount) + '\\';

                for i := 0 to AcceptedCount - 1 do begin
                    AcceptedArray.Get(i, JsonToken);
                    if JsonToken.IsObject() then begin
                        DocumentJson := JsonToken.AsObject();

                        if DocumentJson.Get('uuid', JsonToken) then
                            Uuid := CleanQuotesFromText(SafeJsonValueToText(JsonToken));
                        if DocumentJson.Get('invoiceCodeNumber', JsonToken) then
                            InvoiceCodeNumber := CleanQuotesFromText(SafeJsonValueToText(JsonToken));

                        FormattedResponse += StrSubstNo('- Credit Memo: %1\\    UUID: %2', InvoiceCodeNumber, Uuid);
                        if i < AcceptedCount - 1 then
                            FormattedResponse += '\\';
                    end;
                end;
            end;
        end;

        // Extract rejected documents
        if ResponseJson.Get('rejectedDocuments', JsonToken) and JsonToken.IsArray() then begin
            RejectedArray := JsonToken.AsArray();
            RejectedCount := RejectedArray.Count();

            if RejectedCount > 0 then begin
                if FormattedResponse <> '' then
                    FormattedResponse += '\\';
                FormattedResponse += 'Rejected Documents: ' + Format(RejectedCount);
            end;
        end;

        // If no structured data found, return simplified raw response
        if FormattedResponse = '' then begin
            FormattedResponse := 'Raw Response: ' + CopyStr(RawResponse, 1, 200) + '...';
        end;

        exit(FormattedResponse);
    end;

    /// <summary>
    /// Safely converts JSON token to text
    /// </summary>
    /// <param name="JsonToken">JSON token to convert</param>
    /// <returns>Text representation of the JSON value</returns>
    local procedure SafeJsonValueToText(JsonToken: JsonToken): Text
    begin
        if JsonToken.IsValue() then begin
            exit(Format(JsonToken.AsValue()));
        end else if JsonToken.IsObject() then begin
            exit('JSON Object');
        end else if JsonToken.IsArray() then begin
            exit('JSON Array');
        end else begin
            exit('Unknown');
        end;
    end;

    /// <summary>
    /// Extract detailed error information from LHDN API response for failed submissions
    /// </summary>
    /// <param name="LhdnResponse">Raw JSON response from LHDN API</param>
    /// <returns>Formatted error details for user display</returns>
    local procedure ExtractLhdnErrorDetails(LhdnResponse: Text): Text
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        RejectedArray: JsonArray;
        RejectedDoc: JsonObject;
        ErrorObj: JsonObject;
        DetailsArray: JsonArray;
        DetailObj: JsonObject;
        ErrorCode: Text;
        ErrorMessage: Text;
        Target: Text;
        PropertyPath: Text;
        ErrorDetails: Text;
        i: Integer;
        j: Integer;
    begin
        if not ResponseJson.ReadFrom(LhdnResponse) then
            exit('Failed to parse LHDN response');

        ErrorDetails := 'LHDN Submission Failed\\';

        // Extract submission UID
        if ResponseJson.Get('submissionUid', JsonToken) then begin
            if JsonToken.AsValue().AsText() <> '' then
                ErrorDetails += StrSubstNo('Submission ID: %1\\', JsonToken.AsValue().AsText())
            else
                ErrorDetails += 'Submission ID: null\\';
        end;

        // Extract rejected documents and their errors
        if ResponseJson.Get('rejectedDocuments', JsonToken) and JsonToken.IsArray() then begin
            RejectedArray := JsonToken.AsArray();
            ErrorDetails += StrSubstNo('Rejected Documents: %1\\', Format(RejectedArray.Count()));

            for i := 0 to RejectedArray.Count() - 1 do begin
                RejectedArray.Get(i, JsonToken);
                if JsonToken.IsObject() then begin
                    RejectedDoc := JsonToken.AsObject();

                    // Get credit memo code number
                    if RejectedDoc.Get('invoiceCodeNumber', JsonToken) then
                        ErrorDetails += StrSubstNo('\\Credit Memo: %1\\', JsonToken.AsValue().AsText());

                    // Get error details
                    if RejectedDoc.Get('error', JsonToken) and JsonToken.IsObject() then begin
                        ErrorObj := JsonToken.AsObject();

                        // Get main error information
                        if ErrorObj.Get('code', JsonToken) then
                            ErrorCode := JsonToken.AsValue().AsText();
                        if ErrorObj.Get('message', JsonToken) then
                            ErrorMessage := JsonToken.AsValue().AsText();
                        if ErrorObj.Get('target', JsonToken) then
                            Target := JsonToken.AsValue().AsText();

                        ErrorDetails += StrSubstNo('Error: %1 - %2 (Target: %3)\\',
                                                 ErrorCode, ErrorMessage, Target);

                        // Get detailed validation errors
                        if ErrorObj.Get('details', JsonToken) and JsonToken.IsArray() then begin
                            DetailsArray := JsonToken.AsArray();
                            ErrorDetails += 'Validation Errors:\\';

                            for j := 0 to DetailsArray.Count() - 1 do begin
                                DetailsArray.Get(j, JsonToken);
                                if JsonToken.IsObject() then begin
                                    DetailObj := JsonToken.AsObject();

                                    // Extract error details
                                    if DetailObj.Get('code', JsonToken) then
                                        ErrorCode := JsonToken.AsValue().AsText();
                                    if DetailObj.Get('message', JsonToken) then
                                        ErrorMessage := JsonToken.AsValue().AsText();
                                    if DetailObj.Get('target', JsonToken) then
                                        Target := JsonToken.AsValue().AsText();
                                    if DetailObj.Get('propertyPath', JsonToken) then
                                        PropertyPath := JsonToken.AsValue().AsText();

                                    ErrorDetails += StrSubstNo('  • %1: %2 (Field: %3)\\',
                                                             ErrorCode, ErrorMessage, Target);

                                    if PropertyPath <> '' then
                                        ErrorDetails += StrSubstNo('    Path: %1\\', PropertyPath);
                                end;
                            end;
                        end;
                    end;
                end;
            end;
        end;

        // Add accepted documents count if any
        if ResponseJson.Get('acceptedDocuments', JsonToken) and JsonToken.IsArray() then begin
            RejectedArray := JsonToken.AsArray();
            ErrorDetails += StrSubstNo('\\Accepted Documents: %1', Format(RejectedArray.Count()));
        end;

        ErrorDetails += '\\Please review the errors and resubmit.';
        exit(ErrorDetails);
    end;

    /// <summary>
    /// Display comprehensive LHDN submission error to user with actionable information
    /// </summary>
    /// <param name="ErrorDetails">Formatted error details</param>
    /// <param name="LhdnResponse">Raw LHDN response for debugging</param>
    local procedure ShowLhdnSubmissionError(ErrorDetails: Text; LhdnResponse: Text)
    var
        ErrorMsg: Text;
    begin
        // Show detailed error message
        ErrorMsg := StrSubstNo('LHDN Submission Failed for Credit Memo %1\\', Rec."No.");
        ErrorMsg += '\\Please review the detailed error information below.';

        Message(ErrorMsg);

        // Show detailed error information in a message
        Message(ErrorDetails);
    end;

    /// <summary>
    /// Extract status from LHDN API response for display purposes
    /// Checks both submission-level overallStatus and document-level status for accurate cancellation detection
    /// </summary>
    /// <param name="ResponseText">JSON response from LHDN API</param>
    /// <returns>The formatted status value</returns>
    local procedure ExtractStatusFromApiResponse(ResponseText: Text): Text
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummaryArray: JsonArray;
        DocumentJson: JsonObject;
        OverallStatus: Text;
        DocumentStatus: Text;
        DocumentUuid: Text;
        i: Integer;
    begin
        // Parse the JSON response
        if not JsonObject.ReadFrom(ResponseText) then
            exit('Unknown - JSON Parse Failed');

        // Extract the overallStatus field (submission level)
        if JsonObject.Get('overallStatus', JsonToken) then
            OverallStatus := JsonToken.AsValue().AsText()
        else
            exit('Unknown - No Status Field');

        // Check document-level status for cancellation detection
        if JsonObject.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocumentSummaryArray := JsonToken.AsArray();

            // Look for our specific document by UUID match
            for i := 0 to DocumentSummaryArray.Count() - 1 do begin
                DocumentSummaryArray.Get(i, JsonToken);
                if JsonToken.IsObject() then begin
                    DocumentJson := JsonToken.AsObject();

                    // Get document UUID and status
                    if DocumentJson.Get('uuid', JsonToken) then
                        DocumentUuid := CleanQuotesFromText(SafeJsonValueToText(JsonToken));

                    // If this is our document (UUID match), check its individual status
                    if (DocumentUuid = Rec."eInvoice UUID") and DocumentJson.Get('status', JsonToken) then begin
                        DocumentStatus := CleanQuotesFromText(SafeJsonValueToText(JsonToken));

                        // Document-level status takes precedence for cancellation
                        case DocumentStatus.ToLower() of
                            'cancelled':
                                exit('Cancelled');
                            'valid':
                                exit('Valid');
                            'invalid':
                                exit('Invalid');
                            'rejected':
                                exit('Rejected');
                            else
                                exit(DocumentStatus); // Use document status as-is
                        end;
                    end;
                end;
            end;
        end;

        // Fall back to overall status if no document-specific status found
        case OverallStatus.ToLower() of
            'valid':
                exit('Valid');
            'invalid':
                exit('Invalid');
            'in progress':
                exit('In Progress');
            'partially valid':
                exit('Partially Valid');
            else
                exit(OverallStatus); // Use as-is if unknown
        end;
    end;

    /// <summary>
    /// Automatically generates QR image for the credit memo using the validation URL
    /// This is called after the QR URL is updated during status refresh
    /// </summary>
    /// <param name="CreditMemoNo">The credit memo number to generate QR for</param>
    /// <param name="ValidationUrl">The validation URL to convert to QR</param>
    local procedure AutoGenerateCreditMemoQrImage(CreditMemoNo: Code[20]; ValidationUrl: Text)
    var
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        QrServiceUrl: Text;
        InS: InStream;
        eInvoiceQrManager: Codeunit "eInvoice QR Manager";
        Success: Boolean;
    begin
        if (CreditMemoNo = '') or (ValidationUrl = '') then
            exit;

        // Use a QR generation service to render the QR image from the validation URL
        QrServiceUrl := StrSubstNo('https://quickchart.io/qr?text=%1&size=220', ValidationUrl);

        if not HttpClient.Get(QrServiceUrl, Response) then begin
            // Silently fail - this is an automatic process
            exit;
        end;

        if not Response.IsSuccessStatusCode then begin
            // Silently fail - this is an automatic process
            exit;
        end;

        Response.Content().ReadAs(InS);

        // Generate and store the QR image using the QR Manager
        Success := eInvoiceQrManager.UpdateCreditMemoQrImage(CreditMemoNo, InS, 'eInvoiceQR.png');

        if Success then begin
            // Update the page to show the new QR image
            CurrPage.Update(false);
        end;
    end;

    /// <summary>
    /// Updates the submission log with the response from LHDN API
    /// </summary>
    /// <param name="DocNo">Document number</param>
    /// <param name="NewStatus">New status for the submission log</param>
    /// <param name="LhdnResponse">Raw LHDN API response</param>
    /// <param name="CustomerName">Customer name for the submission log</param>
    /// <param name="ErrorDetails">Detailed error message for failed submissions</param>
    local procedure UpdateSubmissionLogWithResponse(DocNo: Code[20]; NewStatus: Text; LhdnResponse: Text; CustomerName: Text[100]; ErrorDetails: Text)
    var
        SubmissionLog: Record "eInvoice Submission Log";
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        TotalAmount: Decimal;
        TotalAmountInclVAT: Decimal;
    begin
        // Calculate amounts from sales credit memo lines (consistent with JSON generation)
        TotalAmount := 0;
        TotalAmountInclVAT := 0;
        SalesCrMemoLine.SetRange("Document No.", DocNo);
        if SalesCrMemoLine.FindSet() then
            repeat
                TotalAmount += SalesCrMemoLine.Amount;
                TotalAmountInclVAT += SalesCrMemoLine."Amount Including VAT";
            until SalesCrMemoLine.Next() = 0;

        // Try to find existing log entry for this credit memo and submission UID
        SubmissionLog.SetRange("Invoice No.", DocNo);
        SubmissionLog.SetRange("Submission UID", Rec."eInvoice Submission UID");

        if SubmissionLog.FindLast() then begin
            // Update existing log entry
            SubmissionLog.Status := NewStatus;
            SubmissionLog."Last Updated" := CurrentDateTime;
            SubmissionLog."Customer Name" := CustomerName;
            SubmissionLog."Error Message" := ErrorDetails;
            SubmissionLog."Document Type" := Rec."eInvoice Document Type";
            SubmissionLog."Amount" := TotalAmount;
            SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
            if SubmissionLog.Modify() then begin
                // Successfully updated log
            end;
        end else begin
            // Create new log entry if none exists
            SubmissionLog.Init();
            SubmissionLog."Invoice No." := DocNo;
            SubmissionLog."Customer No." := Rec."Sell-to Customer No.";
            SubmissionLog."Amount" := TotalAmount;
            SubmissionLog."Amount Including VAT" := TotalAmountInclVAT;
            SubmissionLog."Submission UID" := Rec."eInvoice Submission UID";
            SubmissionLog."Document UUID" := Rec."eInvoice UUID";
            SubmissionLog.Status := NewStatus;
            SubmissionLog."Customer Name" := CustomerName;
            SubmissionLog."Submission Date" := CurrentDateTime;
            SubmissionLog."Last Updated" := CurrentDateTime;
            SubmissionLog."Error Message" := ErrorDetails;
            SubmissionLog."Document Type" := Rec."eInvoice Document Type";
            if SubmissionLog.Insert() then begin
                // Successfully created log entry
            end;
        end;
    end;
}
