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
    begin
        AllLogs.SetRange("Invoice No.", InvoiceNo);
        if DocType <> '' then
            AllLogs.SetRange("Document Type", DocType);
        AllLogs.SetCurrentKey("Entry No.");
        AllLogs.SetAscending("Entry No.", true);
        if not AllLogs.FindSet() then
            exit(false);

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
            HistoryEntry.Add('ErrorMessage', CopyStr(AllLogs."Error Message", 1, 200));
            HistoryEntry.Add('UserID', AllLogs."User ID");
            HistoryArray.Add(HistoryEntry);
        until AllLogs.Next() = 0;

        AllLogs.FindLast();
        LatestLog := AllLogs;
        if HistoryArray.Count() > 1 then
            HistoryArray.RemoveAt(HistoryArray.Count() - 1);
        if HistoryArray.Count() > 0 then begin
            HistoryArray.WriteTo(HistoryText);
            Clear(LatestLog."Submission History");
            LatestLog."Submission History".CreateOutStream(OutStream);
            OutStream.WriteText(HistoryText);
        end;
        LatestLog."Attempt Number" := AttemptNo;
        LatestLog.Modify(false);

        OlderLog.SetRange("Invoice No.", InvoiceNo);
        if DocType <> '' then
            OlderLog.SetRange("Document Type", DocType);
        OlderLog.SetFilter("Entry No.", '<%1', LatestLog."Entry No.");
        if OlderLog.FindSet(true) then
            repeat
                OlderLog.Delete(false);
            until OlderLog.Next() = 0;
        exit(true);
    end;
}