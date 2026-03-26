pageextension 50321 "Posted Sales Invoices Ext" extends "Posted Sales Invoices"
{
    layout
    {
        addlast(Control1)  // Control1 is the repeater in Posted Sales Invoices list
        {
            field("Latest Submission Status"; GetLatestSubmissionStatus())
            {
                ApplicationArea = All;
                Caption = 'Latest Status (from Log)';
                ToolTip = 'Latest submission status from submission log';
            }

            field("Latest Submission Date"; Rec."Latest Submission Date")
            {
                ApplicationArea = All;
                Caption = 'Latest Submission Date';
                ToolTip = 'Date and time when the invoice was last submitted to LHDN MyInvois';
            }

            field("Latest Error Message"; Rec."Latest Error Message")
            {
                ApplicationArea = All;
                Caption = 'Latest Error Message';
                ToolTip = 'Error message from the most recent submission attempt (if any)';
            }
        }
    }

    actions
    {
        addlast(processing)
        {
            action(SignAndSubmitSelectedToLHDN)
            {
                Caption = 'Sign & Submit to LHDN';
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                Image = ElectronicDoc;
                ToolTip = 'Digitally sign via Azure Function and submit selected posted invoices to LHDN.';

                trigger OnAction()
                var
                    SelectedInvoices: Record "Sales Invoice Header";
                    InvoiceHeader: Record "Sales Invoice Header";
                    eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
                    LhdnResponse: Text;
                    SuccessCount: Integer;
                    FailCount: Integer;
                    Window: Dialog;
                    ProgressLbl: Label 'Submitting #1###### of #2######';
                    Counter: Integer;
                    Total: Integer;
                    TempSelected: Record "Sales Invoice Header" temporary;
                begin
                    CurrPage.SetSelectionFilter(SelectedInvoices);
                    if SelectedInvoices.IsEmpty() then
                        SelectedInvoices.CopyFilters(Rec);

                    // Snapshot selected document numbers into a temporary record to survive commits
                    if SelectedInvoices.FindSet() then
                        repeat
                            TempSelected.Init();
                            TempSelected."No." := SelectedInvoices."No.";
                            TempSelected.Insert();
                        until SelectedInvoices.Next() = 0;

                    Total := TempSelected.Count;
                    if Total = 0 then
                        exit;

                    Window.Open(ProgressLbl);
                    Window.Update(2, Total);

                    eInvoiceGenerator.SetSuppressUserDialogs(true);

                    if TempSelected.FindSet() then
                        repeat
                            Counter += 1;
                            Window.Update(1, Counter);

                            if InvoiceHeader.Get(TempSelected."No.") then begin
                                if eInvoiceGenerator.GetSignedInvoiceAndSubmitToLHDN(InvoiceHeader, LhdnResponse) then begin
                                    SuccessCount += 1;
                                    SendInlineNotification(true, InvoiceHeader."No.", LhdnResponse);
                                end else begin
                                    FailCount += 1;
                                    SendInlineNotification(false, InvoiceHeader."No.", LhdnResponse);
                                end;
                            end else begin
                                FailCount += 1;
                            end;
                        until TempSelected.Next() = 0;

                    Window.Close();
                    Message('LHDN submission completed. Success: %1  Failed: %2', SuccessCount, FailCount);
                end;
            }

            action(ExportToExcel)
            {
                Caption = 'Export to Excel';
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                Image = ExportToExcel;
                ToolTip = 'Export selected sales invoices to Excel';

                trigger OnAction()
                begin
                    ExportPostedSalesInvoices(Rec);
                end;
            }
        }
    }

    local procedure SendInlineNotification(Success: Boolean; DocNo: Code[20]; LhdnResponse: Text)
    var
        Notif: Notification;
        Msg: Text;
    begin
        if Success then
            Msg := StrSubstNo('LHDN submission successful for Invoice %1. %2', DocNo, FormatLhdnResponseInline(LhdnResponse))
        else
            Msg := StrSubstNo('LHDN submission failed for Invoice %1. Response: %2', DocNo, CopyStr(LhdnResponse, 1, 250));

        Notif.Scope := NotificationScope::LocalScope;
        Notif.Message(Msg);
        Notif.Send();
    end;

    local procedure FormatLhdnResponseInline(RawResponse: Text): Text
    var
        ResponseJson: JsonObject;
        JsonToken: JsonToken;
        AcceptedArray: JsonArray;
        SubmissionUid: Text;
        AcceptedCount: Integer;
        DocumentJson: JsonObject;
        InvoiceCodeNumber: Text;
        Uuid: Text;
        Summary: Text;
    begin
        if not ResponseJson.ReadFrom(RawResponse) then
            exit(StrSubstNo('Raw Response: %1', CopyStr(RawResponse, 1, 200)));

        if ResponseJson.Get('submissionUid', JsonToken) then
            SubmissionUid := CleanQuotesFromText(JsonToken.AsValue().AsText());

        if ResponseJson.Get('acceptedDocuments', JsonToken) and JsonToken.IsArray() then begin
            AcceptedArray := JsonToken.AsArray();
            AcceptedCount := AcceptedArray.Count();
            if AcceptedCount > 0 then begin
                AcceptedArray.Get(0, JsonToken);
                if JsonToken.IsObject() then begin
                    DocumentJson := JsonToken.AsObject();
                    if DocumentJson.Get('invoiceCodeNumber', JsonToken) then
                        InvoiceCodeNumber := CleanQuotesFromText(JsonToken.AsValue().AsText());
                    if DocumentJson.Get('uuid', JsonToken) then
                        Uuid := CleanQuotesFromText(JsonToken.AsValue().AsText());
                end;
            end;
        end;

        Summary := StrSubstNo('Submission ID: %1 | Accepted Documents: %2', SubmissionUid, Format(AcceptedCount));
        if InvoiceCodeNumber <> '' then
            Summary += StrSubstNo(' | Invoice: %1', InvoiceCodeNumber);
        if Uuid <> '' then
            Summary += StrSubstNo(' | UUID: %1', Uuid);

        exit(Summary);
    end;

    local procedure CleanQuotesFromText(Value: Text): Text
    begin
        Value := DelChr(Value, '<>', '"');
        exit(Value);
    end;

    local procedure ExportPostedSalesInvoices(var SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        TempExcelBuffer: Record "Excel Buffer" temporary;
        SalesInvoiceLine: Record "Sales Invoice Line";
        Window: Dialog;
        Counter: Integer;
        TotalCount: Integer;
        ExcelFileName: Text;
        ProgressLbl: Label 'Exporting invoices #1###### of #2######';
    begin
        // Set filters and count records
        SalesInvoiceHeader.CopyFilters(Rec);
        TotalCount := SalesInvoiceHeader.Count();

        // Initialize progress window
        Window.Open(ProgressLbl);
        Window.Update(1, 0);
        Window.Update(2, TotalCount);

        // Prepare Excel file name with timestamp
        ExcelFileName := 'SalesInvoices_' + Format(Today, 0, '<Year4><Month,2><Day,2>') + '_' +
                         Format(Time, 0, '<Hours24,2><Filler Character,0><Minutes,2><Seconds,2>') + '.xlsx';

        // Initialize Excel buffer
        TempExcelBuffer.Reset();
        TempExcelBuffer.DeleteAll();

        // Process records
        if SalesInvoiceHeader.FindSet() then
            repeat
                Counter += 1;
                if Counter mod 50 = 0 then begin
                    Window.Update(1, Counter);
                    Commit();
                end;

                // Add invoice header section
                AddInvoiceSectionToExcel(TempExcelBuffer, SalesInvoiceHeader);

                // Add invoice lines
                SalesInvoiceLine.SetRange("Document No.", SalesInvoiceHeader."No.");
                if SalesInvoiceLine.FindSet() then
                    repeat
                        AddInvoiceLineToExcel(TempExcelBuffer, SalesInvoiceLine);
                    until SalesInvoiceLine.Next() = 0;

                // Add separator between invoices
                TempExcelBuffer.NewRow();
                TempExcelBuffer.NewRow();
            until SalesInvoiceHeader.Next() = 0;

        Window.Close();

        // Generate and open Excel file
        GenerateExcelFile(TempExcelBuffer, ExcelFileName);
    end;

    local procedure AddInvoiceSectionToExcel(var TempExcelBuffer: Record "Excel Buffer"; SalesInvoiceHeader: Record "Sales Invoice Header")
    begin
        // Invoice header
        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Invoice No.:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesInvoiceHeader."No.", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);

        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Posting Date:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesInvoiceHeader."Posting Date", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Date);

        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Customer:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesInvoiceHeader."Sell-to Customer No." + ' - ' + SalesInvoiceHeader."Sell-to Customer Name",
                                false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);

        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Amount:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesInvoiceHeader.Amount, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);

        // Line items header
        TempExcelBuffer.NewRow();
        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('LINE ITEMS', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);

        TempExcelBuffer.NewRow();
        AddExcelHeader(TempExcelBuffer, 'Line No.');
        AddExcelHeader(TempExcelBuffer, 'Type');
        AddExcelHeader(TempExcelBuffer, 'No.');
        AddExcelHeader(TempExcelBuffer, 'Description');
        AddExcelHeader(TempExcelBuffer, 'Quantity');
        AddExcelHeader(TempExcelBuffer, 'Unit Price');
        AddExcelHeader(TempExcelBuffer, 'Line Amount');
    end;

    local procedure AddExcelHeader(var TempExcelBuffer: Record "Excel Buffer"; HeaderText: Text)
    begin
        TempExcelBuffer.AddColumn(
            HeaderText, false, '', true, false, false,
            '', TempExcelBuffer."Cell Type"::Text);
    end;

    local procedure AddInvoiceLineToExcel(var TempExcelBuffer: Record "Excel Buffer"; SalesInvoiceLine: Record "Sales Invoice Line")
    begin
        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn(SalesInvoiceLine."Line No.", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(Format(SalesInvoiceLine.Type), false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesInvoiceLine."No.", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesInvoiceLine.Description, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesInvoiceLine.Quantity, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);
        TempExcelBuffer.AddColumn(SalesInvoiceLine."Unit Price", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);
        TempExcelBuffer.AddColumn(SalesInvoiceLine."Line Amount", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);
    end;

    local procedure GenerateExcelFile(var TempExcelBuffer: Record "Excel Buffer"; FileName: Text)
    begin
        TempExcelBuffer.CreateNewBook('Sales Invoices');
        TempExcelBuffer.WriteSheet('Sales Invoices', CompanyName, UserId);
        TempExcelBuffer.CloseBook();
        TempExcelBuffer.SetFriendlyFilename(FileName);
        TempExcelBuffer.OpenExcel();
    end;

    // Procedure needed for Latest Status field
    local procedure GetLatestSubmissionStatus(): Text[50]
    var
        SubmissionLog: Record "eInvoice Submission Log";
    begin
        SubmissionLog.SetRange("Invoice No.", Rec."No.");
        if SubmissionLog.FindLast() then
            exit(SubmissionLog.Status);
        exit('');
    end;
}