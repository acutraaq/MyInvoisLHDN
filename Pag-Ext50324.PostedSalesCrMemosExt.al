pageextension 50324 "Posted Sales Cr Memos Ext" extends "Posted Sales Credit Memos"
{
    layout
    {
        addlast(Control1)  // Control1 is the repeater in Posted Sales Credit Memos list
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
                ToolTip = 'Date and time when the credit memo was last submitted to LHDN MyInvois';
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
                ToolTip = 'Digitally sign via Azure Function and submit selected posted credit memos to LHDN.';

                trigger OnAction()
                var
                    SelectedCreditMemos: Record "Sales Cr.Memo Header";
                    CreditMemoHeader: Record "Sales Cr.Memo Header";
                    eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
                    LhdnResponse: Text;
                    SuccessCount: Integer;
                    FailCount: Integer;
                    Window: Dialog;
                    ProgressLbl: Label 'Submitting #1###### of #2######';
                    Counter: Integer;
                    Total: Integer;
                    TempSelected: Record "Sales Cr.Memo Header" temporary;
                begin
                    CurrPage.SetSelectionFilter(SelectedCreditMemos);
                    if SelectedCreditMemos.IsEmpty() then
                        SelectedCreditMemos.CopyFilters(Rec);

                    // Snapshot selected document numbers into a temporary record to survive commits
                    if SelectedCreditMemos.FindSet() then
                        repeat
                            TempSelected.Init();
                            TempSelected."No." := SelectedCreditMemos."No.";
                            TempSelected.Insert();
                        until SelectedCreditMemos.Next() = 0;

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

                            if CreditMemoHeader.Get(TempSelected."No.") then begin
                                if eInvoiceGenerator.GetSignedCreditMemoAndSubmitToLHDN(CreditMemoHeader, LhdnResponse) then begin
                                    SuccessCount += 1;
                                    SendInlineNotification(true, CreditMemoHeader."No.", LhdnResponse);
                                end else begin
                                    FailCount += 1;
                                    SendInlineNotification(false, CreditMemoHeader."No.", LhdnResponse);
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
                ToolTip = 'Export selected sales credit memos to Excel';

                trigger OnAction()
                begin
                    ExportPostedSalesCreditMemos(Rec);
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
            Msg := StrSubstNo('LHDN submission successful for Credit Memo %1. %2', DocNo, FormatLhdnResponseInline(LhdnResponse))
        else
            Msg := StrSubstNo('LHDN submission failed for Credit Memo %1. Response: %2', DocNo, CopyStr(LhdnResponse, 1, 250));

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
            Summary += StrSubstNo(' | Credit Memo: %1', InvoiceCodeNumber);
        if Uuid <> '' then
            Summary += StrSubstNo(' | UUID: %1', Uuid);

        exit(Summary);
    end;

    local procedure CleanQuotesFromText(Value: Text): Text
    begin
        Value := DelChr(Value, '<>', '"');
        exit(Value);
    end;

    local procedure ExportPostedSalesCreditMemos(var SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        TempExcelBuffer: Record "Excel Buffer" temporary;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        Window: Dialog;
        Counter: Integer;
        TotalCount: Integer;
        ExcelFileName: Text;
        ProgressLbl: Label 'Exporting credit memos #1###### of #2######';
    begin
        // Set filters and count records
        SalesCrMemoHeader.CopyFilters(Rec);
        TotalCount := SalesCrMemoHeader.Count();

        // Initialize progress window
        Window.Open(ProgressLbl);
        Window.Update(1, 0);
        Window.Update(2, TotalCount);

        // Prepare Excel file name with timestamp
        ExcelFileName := 'SalesCreditMemos_' + Format(Today, 0, '<Year4><Month,2><Day,2>') + '_' +
                         Format(Time, 0, '<Hours24,2><Filler Character,0><Minutes,2><Seconds,2>') + '.xlsx';

        // Initialize Excel buffer
        TempExcelBuffer.Reset();
        TempExcelBuffer.DeleteAll();

        // Process records
        if SalesCrMemoHeader.FindSet() then
            repeat
                Counter += 1;
                if Counter mod 50 = 0 then begin
                    Window.Update(1, Counter);
                    Commit();
                end;

                // Add credit memo header section
                AddCreditMemoSectionToExcel(TempExcelBuffer, SalesCrMemoHeader);

                // Add credit memo lines
                SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
                if SalesCrMemoLine.FindSet() then
                    repeat
                        AddCreditMemoLineToExcel(TempExcelBuffer, SalesCrMemoLine);
                    until SalesCrMemoLine.Next() = 0;

                // Add separator between credit memos
                TempExcelBuffer.NewRow();
                TempExcelBuffer.NewRow();
            until SalesCrMemoHeader.Next() = 0;

        Window.Close();

        // Generate and open Excel file
        GenerateExcelFile(TempExcelBuffer, ExcelFileName);
    end;

    local procedure AddCreditMemoSectionToExcel(var TempExcelBuffer: Record "Excel Buffer"; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    begin
        // Credit memo header
        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Credit Memo No.:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesCrMemoHeader."No.", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);

        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Posting Date:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesCrMemoHeader."Posting Date", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Date);

        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Customer:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesCrMemoHeader."Sell-to Customer No." + ' - ' + SalesCrMemoHeader."Sell-to Customer Name",
                                false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);

        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn('Amount:', false, '', true, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesCrMemoHeader.Amount, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);

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

    local procedure AddCreditMemoLineToExcel(var TempExcelBuffer: Record "Excel Buffer"; SalesCrMemoLine: Record "Sales Cr.Memo Line")
    begin
        TempExcelBuffer.NewRow();
        TempExcelBuffer.AddColumn(SalesCrMemoLine."Line No.", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(Format(SalesCrMemoLine.Type), false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesCrMemoLine."No.", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesCrMemoLine.Description, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Text);
        TempExcelBuffer.AddColumn(SalesCrMemoLine.Quantity, false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);
        TempExcelBuffer.AddColumn(SalesCrMemoLine."Unit Price", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);
        TempExcelBuffer.AddColumn(SalesCrMemoLine."Line Amount", false, '', false, false, false, '', TempExcelBuffer."Cell Type"::Number);
    end;

    local procedure GenerateExcelFile(var TempExcelBuffer: Record "Excel Buffer"; FileName: Text)
    begin
        TempExcelBuffer.CreateNewBook('Sales Credit Memos');
        TempExcelBuffer.WriteSheet('Sales Credit Memos', CompanyName, UserId);
        TempExcelBuffer.CloseBook();
        TempExcelBuffer.SetFriendlyFilename(FileName);
        TempExcelBuffer.OpenExcel();
    end;

    // Procedure needed for latest submission status field
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