codeunit 50327 "eInvoice Log Consolidation"
{
    Permissions = tabledata "eInvoice Submission Log" = RIMD;

    procedure ConsolidateDuplicateSubmissionLogs(): Integer
    var
        SubmissionLog: Record "eInvoice Submission Log";
        ProcessedCombos: List of [Text];
        InvoiceKey: Text;
        ConsolidatedCount: Integer;
    begin
        ConsolidatedCount := 0;
        SubmissionLog.Reset();
        if SubmissionLog.FindSet() then begin
            repeat
                InvoiceKey := SubmissionLog."Invoice No." + '|' + SubmissionLog."Document Type";
                if not ProcessedCombos.Contains(InvoiceKey) then begin
                    ProcessedCombos.Add(InvoiceKey);
                    if CountSubmissionsForInvoice(SubmissionLog."Invoice No.", SubmissionLog."Document Type") > 1 then begin
                        if ConsolidateInvoiceSubmissions(SubmissionLog."Invoice No.", SubmissionLog."Document Type") then
                            ConsolidatedCount += 1;
                    end;
                end;
            until SubmissionLog.Next() = 0;
        end;
        Message('Consolidation complete. Processed: %1 invoices with multiple submissions', ConsolidatedCount);
        exit(ConsolidatedCount);
    end;

    local procedure CountSubmissionsForInvoice(InvoiceNo: Code[20]; DocType: Code[20]): Integer
    var
        SubmissionLog: Record "eInvoice Submission Log";
    begin
        SubmissionLog.SetRange("Invoice No.", InvoiceNo);
        if DocType <> '' then
            SubmissionLog.SetRange("Document Type", DocType);
        exit(SubmissionLog.Count());
    end;

    local procedure ConsolidateInvoiceSubmissions(InvoiceNo: Code[20]; DocType: Code[20]): Boolean
    var
        AllLogs: Record "eInvoice Submission Log";
        LatestLog: Record "eInvoice Submission Log";
        OlderLog: Record "eInvoice Submission Log";
        HistoryArray: JsonArray;
        HistoryEntry: JsonObject;
        OutStream: OutStream;
        HistoryText: Text;
        AttemptNo: Integer;
        LatestSubmissionDate: DateTime;
    begin
        AllLogs.SetRange("Invoice No.", InvoiceNo);
        if DocType <> '' then
            AllLogs.SetRange("Document Type", DocType);

        // CHANGED: Sort by Submission Date instead of Entry No.
        AllLogs.SetCurrentKey("Submission Date");
        AllLogs.SetAscending("Submission Date", true);

        if not AllLogs.FindSet() then
            exit(false);

        // Build history from ALL attempts
        AttemptNo := 0;
        repeat
            AttemptNo += 1;
            Clear(HistoryEntry);
            HistoryEntry.Add('AttemptNo', AttemptNo);
            HistoryEntry.Add('EntryNo', AllLogs."Entry No.");
            HistoryEntry.Add('SubmissionUID', AllLogs."Submission UID");
            HistoryEntry.Add('DocumentUUID', AllLogs."Document UUID");
            HistoryEntry.Add('Status', AllLogs.Status);
            HistoryEntry.Add('SubmissionDate', Format(AllLogs."Submission Date", 0, 9));
            HistoryEntry.Add('ResponseDate', Format(AllLogs."Response Date", 0, 9));
            HistoryEntry.Add('ErrorMessage', AllLogs."Error Message");
            HistoryEntry.Add('ErrorCode', AllLogs."Error Code");
            HistoryEntry.Add('ErrorPropertyPath', AllLogs."Error Property Path");
            HistoryEntry.Add('ErrorEnglish', AllLogs."Error English");
            HistoryEntry.Add('ErrorMalay', AllLogs."Error Malay");
            HistoryEntry.Add('ErrorTarget', AllLogs."Error Target");
            HistoryEntry.Add('HTTPStatusCode', Format(AllLogs."HTTP Status Code"));
            HistoryEntry.Add('CorrelationID', AllLogs."Correlation ID");
            HistoryEntry.Add('UserID', AllLogs."User ID");
            HistoryEntry.Add('CustomerName', AllLogs."Customer Name");
            HistoryEntry.Add('Amount', Format(AllLogs.Amount));
            HistoryEntry.Add('AmountInclVAT', Format(AllLogs."Amount Including VAT"));
            HistoryEntry.Add('Environment', Format(AllLogs.Environment));
            HistoryArray.Add(HistoryEntry);
        until AllLogs.Next() = 0;

        // CHANGED: Find the entry with the LATEST Submission Date
        AllLogs.Reset();
        AllLogs.SetRange("Invoice No.", InvoiceNo);
        if DocType <> '' then
            AllLogs.SetRange("Document Type", DocType);
        AllLogs.SetCurrentKey("Submission Date");
        AllLogs.SetAscending("Submission Date", false); // Descending to get latest first
        AllLogs.FindFirst();
        LatestLog := AllLogs;
        LatestSubmissionDate := LatestLog."Submission Date";

        // Remove the latest entry from history (it will be the current record)
        if HistoryArray.Count() > 1 then
            HistoryArray.RemoveAt(HistoryArray.Count() - 1);

        // ENHANCED: Store history in the latest log entry with validation
        if HistoryArray.Count() > 0 then begin
            Clear(HistoryText);
            HistoryArray.WriteTo(HistoryText);

            // ADDED: Validate that JSON was actually written
            if HistoryText = '' then
                Error('Failed to serialize history array to JSON for invoice %1. Array count was %2 but WriteTo returned empty string.', InvoiceNo, HistoryArray.Count());

            // ADDED: Validate JSON length is reasonable
            if StrLen(HistoryText) < 10 then
                Error('JSON serialization produced suspiciously short output (%1 chars) for invoice %2. Expected valid JSON array.', StrLen(HistoryText), InvoiceNo);

            // CHANGED: Clear BLOB and write with explicit UTF8 encoding to match read operation
            Clear(LatestLog."Submission History");
            LatestLog."Submission History".CreateOutStream(OutStream, TextEncoding::UTF8);
            OutStream.WriteText(HistoryText);
            LatestLog."Attempt Number" := AttemptNo;

            // ADDED: Validate that modify succeeded
            if not LatestLog.Modify(false) then
                Error('Failed to save consolidation for invoice %1. Database modify operation failed.', InvoiceNo);
        end else begin
            // ADDED: Handle case where no history (only 1 submission was consolidated)
            // Still update attempt number even if there's no history to archive
            LatestLog."Attempt Number" := AttemptNo;
            if not LatestLog.Modify(false) then
                Error('Failed to update attempt number for invoice %1. Database modify operation failed.', InvoiceNo);
        end;

        // CHANGED: Delete all entries EXCEPT the one with the latest Submission Date
        OlderLog.SetRange("Invoice No.", InvoiceNo);
        if DocType <> '' then
            OlderLog.SetRange("Document Type", DocType);
        OlderLog.SetFilter("Submission Date", '<%1', LatestSubmissionDate);

        if OlderLog.FindSet(true) then
            repeat
                OlderLog.Delete(false);
            until OlderLog.Next() = 0;

        exit(true);
    end;

    /// <summary>
    /// Automatically consolidate duplicates for a specific invoice
    /// Called after creating new submission log entries
    /// </summary>
    procedure AutoConsolidateForInvoice(InvoiceNo: Code[20]; DocType: Code[20])
    var
        SubmissionLog: Record "eInvoice Submission Log";
        Count: Integer;
    begin
        // Check if there are multiple entries for this invoice
        SubmissionLog.SetRange("Invoice No.", InvoiceNo);
        if DocType <> '' then
            SubmissionLog.SetRange("Document Type", DocType);
        Count := SubmissionLog.Count();

        // Only consolidate if there are 2 or more entries
        if Count > 1 then
            ConsolidateInvoiceSubmissions(InvoiceNo, DocType);
    end;
}