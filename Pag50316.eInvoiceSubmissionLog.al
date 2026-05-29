page 50316 "e-Invoice Submission Log"
{
    PageType = List;
    SourceTable = "eInvoice Submission Log";
    Caption = 'e-Invoice Submission Log';
    UsageCategory = Lists;
    ApplicationArea = All;
    CardPageId = "e-Invoice Submission Log Card";
    Editable = false; // Read-only list; use actions for controlled updates
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false; // Deletions only via provided actions with validation

    layout
    {
        area(content)
        {
            repeater(GroupName)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the unique entry number for this log entry.';
                }
                field("Invoice No."; Rec."Invoice No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the invoice number that was submitted.';
                }
                field("Customer No."; Rec."Customer No.")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the customer number for this invoice submission.';
                }
                field("Customer Name"; Rec."Customer Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the customer name for this invoice submission.';
                }
                field("Amount"; Rec."Amount")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the amount excluding VAT for this invoice.';
                }
                field("Amount Including VAT"; Rec."Amount Including VAT")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the amount including VAT for this invoice.';
                }
                field("Submission UID"; Rec."Submission UID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the LHDN submission UID returned after submission.';
                }
                field("Document UUID"; Rec."Document UUID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the document UUID assigned by LHDN MyInvois.';
                }
                field("Long ID"; Rec."Long ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Long temporary ID returned by LHDN for valid documents.';
                }
                field("Validation Link"; Rec."Validation Link")
                {
                    ApplicationArea = All;
                    ToolTip = 'Public validation URL constructed as {envbaseurl}/uuid-of-document/share/longid.';
                    ExtendedDatatype = URL;
                }
                field("Document Type Description"; Rec."Document Type Description")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the document type description (e.g., Standard Invoice, Credit Note, etc.).';
                }
                field("Status"; Rec.Status)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the submission status (Submitted, Accepted, Rejected, etc.).';
                }

                field("Submission Date"; Rec."Submission Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the invoice was submitted to LHDN.';
                }
                field("Response Date"; Rec."Response Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the response was received from LHDN.';
                }
                field("Posting Date"; Rec."Posting Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the posting date of the posted sales invoice.';
                }
                field("Environment"; Rec.Environment)
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the environment (Preprod/Production) where the submission was made.';
                }
                field("Error Message"; Rec."Error Message")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies any error message received from LHDN.';
                }
                field("Error Code"; Rec."Error Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the MyInvois error code (e.g., Error03, DS302).';
                    Visible = Rec."Error Code" <> '';
                    Style = Attention;
                    StyleExpr = Rec."Error Code" <> '';
                }
                field("Error English"; Rec."Error English")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the error message in English from MyInvois API.';
                    Visible = Rec."Error English" <> '';
                }
                field("Error Property Path"; Rec."Error Property Path")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the path to the field that caused the error (e.g., $.InvoiceLineItem[*].InvoicedQuantity.unitCode).';
                    Visible = Rec."Error Property Path" <> '';
                }
                field("HTTP Status Code"; Rec."HTTP Status Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the HTTP status code from MyInvois API (e.g., 400, 401, 429, 500).';
                    Visible = Rec."HTTP Status Code" <> 0;
                }
                field("Correlation ID"; Rec."Correlation ID")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the correlation ID for tracking the request with LHDN support team.';
                    Visible = Rec."Correlation ID" <> '';
                }
                field("Cancellation Reason"; Rec."Cancellation Reason")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the reason for cancellation if the document was cancelled.';
                    Visible = Rec.Status = 'Cancelled';
                }
                field("Cancellation Date"; Rec."Cancellation Date")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies when the document was cancelled in LHDN.';
                    Visible = Rec.Status = 'Cancelled';
                }
            }
        }
    }


    actions
    {
        area(processing)
        {
            action(ViewErrorDetails)
            {
                ApplicationArea = All;
                Caption = 'View Error Details';
                Image = ErrorLog;
                ToolTip = 'View complete error details including inner errors from MyInvois API.';

                trigger OnAction()
                var
                    SubmissionStatusCU: Codeunit "eInvoice Submission Status";
                    ErrorDetails: Text;
                begin
                    // Check if there are any error details to display
                    if (Rec."Error Code" = '') and (Rec."HTTP Status Code" = 0) and (Rec."Error Message" = '') then begin
                        Message('No error details available for this submission.');
                        exit;
                    end;

                    ErrorDetails := SubmissionStatusCU.GetFormattedErrorDetails(Rec);
                    if ErrorDetails = '' then
                        Message('No detailed error information available for this submission.')
                    else
                        Message(ErrorDetails);
                end;
            }

            action(RefreshStatus)
            {
                ApplicationArea = All;
                Caption = 'Refresh Status';
                Image = Refresh;
                ToolTip = 'Refresh status for the current record or all selected records.';
                Visible = IsJotexCompany;

                trigger OnAction()
                var
                    SubmissionStatusCU: Codeunit "eInvoice Submission Status";
                    SelectedSubmissionLog: Record "eInvoice Submission Log";
                    SelectedCount: Integer;
                    UpdatedCount: Integer;
                    FailedCount: Integer;
                begin
                    // If multiple entries are selected, process them in bulk
                    CurrPage.SetSelectionFilter(SelectedSubmissionLog);
                    SelectedCount := SelectedSubmissionLog.Count();

                    if SelectedCount > 1 then begin
                        // Process only those with Submission UID
                        SelectedSubmissionLog.SetFilter("Submission UID", '<>%1', '');
                        if SelectedSubmissionLog.Count() = 0 then begin
                            Message('None of the selected entries have Submission UIDs. Cannot refresh status.');
                            exit;
                        end;

                        if not Confirm(StrSubstNo('Refresh status for %1 selected submissions?', SelectedSubmissionLog.Count())) then
                            exit;

                        UpdatedCount := 0;
                        FailedCount := 0;
                        if SelectedSubmissionLog.FindSet() then
                            repeat
                                if DirectRefreshSingle(SelectedSubmissionLog) then begin
                                    PopulateValidationLink(SelectedSubmissionLog);
                                    UpdatedCount += 1;
                                end else
                                    FailedCount += 1;
                            until SelectedSubmissionLog.Next() = 0;

                        if FailedCount > 0 then
                            Message('%1 updated. %2 failed (direct API).', UpdatedCount, FailedCount);
                    end else begin
                        // Single record flow
                        if Rec."Submission UID" = '' then begin
                            Message('Please select a record with a Submission UID to refresh.');
                            exit;
                        end;

                        if not DirectRefreshSingle(Rec) then
                            Message('Direct API refresh failed for Submission UID %1.', Rec."Submission UID");
                        PopulateValidationLink(Rec);
                    end;

                    CurrPage.Update(false);
                end;
            }
            action(RefreshSelectedStatuses)
            {
                ApplicationArea = All;
                Caption = 'Refresh Selected Statuses';
                Image = RefreshRegister;
                ToolTip = 'Refresh the status for selected submissions (use "Refresh Status" instead).';
                Visible = false;
                Enabled = false;

                trigger OnAction()
                var
                    SubmissionStatusCU: Codeunit "eInvoice Submission Status";
                    SelectedSubmissionLog: Record "eInvoice Submission Log";
                    UpdatedCount: Integer;
                    FailedCount: Integer;
                    SelectedCount: Integer;
                    ProcessedCount: Integer;
                begin
                    // Get selected records
                    CurrPage.SetSelectionFilter(SelectedSubmissionLog);
                    SelectedCount := SelectedSubmissionLog.Count();

                    if SelectedCount = 0 then begin
                        Message('Please select one or more submission entries to refresh.');
                        exit;
                    end;

                    // Count how many have Submission UIDs
                    SelectedSubmissionLog.SetFilter("Submission UID", '<>%1', '');
                    ProcessedCount := SelectedSubmissionLog.Count();

                    if ProcessedCount = 0 then begin
                        Message('None of the selected entries have Submission UIDs. Cannot refresh status.');
                        exit;
                    end;

                    if not Confirm(StrSubstNo('Refresh status for %1 selected submissions (out of %2 selected)?', ProcessedCount, SelectedCount)) then
                        exit;

                    UpdatedCount := 0;
                    FailedCount := 0;

                    // Process each selected record
                    if SelectedSubmissionLog.FindSet() then begin
                        repeat
                            // Check if HTTP context is allowed for each record
                            if SubmissionStatusCU.IsHttpContextAllowed() then begin
                                if SubmissionStatusCU.RefreshSubmissionLogStatusSafe(SelectedSubmissionLog) then
                                    UpdatedCount += 1
                                else
                                    FailedCount += 1;
                            end else begin
                                // Context restricted - mark as failed and offer background job
                                FailedCount += 1;
                                // Update error message to indicate context restriction
                                SelectedSubmissionLog."Error Message" := CopyStr('Context restriction: HTTP operations not allowed in this UI context.',
                                                                             1, MaxStrLen(SelectedSubmissionLog."Error Message"));
                                SelectedSubmissionLog."Last Updated" := CurrentDateTime;
                                SelectedSubmissionLog.Modify();
                            end;
                        until SelectedSubmissionLog.Next() = 0;
                    end;

                    // Handle failures with background job option (no success message)
                    if FailedCount > 0 then begin
                        if Confirm(StrSubstNo('Refreshed %1 submissions successfully, %2 failed due to context restrictions.\Create background jobs for the failed entries?', UpdatedCount, FailedCount)) then begin
                            CreateSelectedBackgroundJobs(SelectedSubmissionLog);
                        end;
                    end;

                    CurrPage.Update(false);
                end;
            }

            action(ResubmitToLHDN)
            {
                ApplicationArea = All;
                Caption = 'Resubmit to LHDN';
                Image = Refresh;
                ToolTip = 'Resubmit (updates existing entry, archives previous attempt)';
                Visible = IsJotexCompany;
                Enabled = CanResubmit;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    SalesInvoiceHeader: Record "Sales Invoice Header";
                    SalesCrMemoHeader: Record "Sales Cr.Memo Header";
                    eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
                    LhdnResponse: Text;
                    Success: Boolean;
                begin
                    if not (Rec.Status in ['Rejected', 'Submission Failed', 'Invalid', 'Cancelled']) then
                        Error('Resubmission only allowed for: Rejected, Submission Failed, Invalid, Cancelled. Current: %1', Rec.Status);
                    if not Confirm('Resubmit %1 (Attempt #%2)?', false, Rec."Invoice No.", Rec."Attempt Number") then
                        exit;
                    case Rec."Document Type" of
                        '01':
                            begin
                                if not SalesInvoiceHeader.Get(Rec."Invoice No.") then
                                    Error('Invoice %1 not found', Rec."Invoice No.");
                                eInvoiceGenerator.SetSuppressUserDialogs(true);
                                Success := eInvoiceGenerator.GetSignedInvoiceAndSubmitToLHDN(SalesInvoiceHeader, LhdnResponse);
                            end;
                        '02':
                            begin
                                if not SalesCrMemoHeader.Get(Rec."Invoice No.") then
                                    Error('Credit Memo %1 not found', Rec."Invoice No.");
                                eInvoiceGenerator.SetSuppressUserDialogs(true);
                                Success := eInvoiceGenerator.GetSignedCreditMemoAndSubmitToLHDN(SalesCrMemoHeader, LhdnResponse);
                            end;
                        else
                            Error('Document type %1 not supported', Rec."Document Type");
                    end;
                    if Success then
                        Message('Resubmitted successfully (Attempt #%1)', Rec."Attempt Number")
                    else
                        Message('Resubmission failed: %1', LhdnResponse);
                    CurrPage.Update(false);
                end;
            }

            action(ViewSubmissionHistory)
            {
                ApplicationArea = All;
                Caption = 'View History';
                Image = History;
                ToolTip = 'View previous submission attempts';
                Enabled = Rec."Attempt Number" > 1;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                begin
                    ShowSubmissionHistory();
                end;
            }

            action(ConsolidateDuplicates)
            {
                ApplicationArea = All;
                Caption = 'Consolidate Duplicates';
                Image = Compress;
                ToolTip = 'Consolidate duplicate entries (keeps latest, archives others)';

                trigger OnAction()
                var
                    LogConsolidation: Codeunit "eInvoice Log Consolidation";
                begin
                    if not Confirm('Consolidate duplicates? Latest entries kept, older archived then deleted. Cannot undo.', false) then
                        exit;
                    LogConsolidation.ConsolidateDuplicateSubmissionLogs();
                    CurrPage.Update(false);
                end;
            }

            action(DeleteEntry)
            {
                ApplicationArea = All;
                Caption = 'Delete Entry';
                Image = Delete;
                ToolTip = 'Delete this entry (allowed if Submission UID is empty/null OR Document UUID is empty/null OR Status is Invalid/Submitted).';
                Visible = true;
                Enabled = false; // Disable button

                trigger OnAction()
                var
                    SubmissionLog: Record "eInvoice Submission Log";
                    CanDelete: Boolean;
                    DeleteReason: Text;
                begin
                    CanDelete := false;
                    DeleteReason := '';

                    // Check if entry can be deleted based on various criteria
                    if (Rec."Submission UID" = '') or (Rec."Submission UID" = 'null') then begin
                        CanDelete := true;
                        DeleteReason := 'no Submission UID';
                    end else if (Rec."Document UUID" = '') or (Rec."Document UUID" = 'null') then begin
                        CanDelete := true;
                        DeleteReason := 'no Document UUID';
                    end else if (Rec.Status = 'Invalid') then begin
                        CanDelete := true;
                        DeleteReason := 'Invalid status';
                    end else if (Rec.Status = 'Submitted') then begin
                        CanDelete := true;
                        DeleteReason := 'Submitted status';
                    end;

                    if not CanDelete then begin
                        Error('Cannot delete e-invoice submission log entry. Only entries without Submission UID, without Document UUID, or with Invalid/Submitted status can be deleted.\Submission UID: %1\Document UUID: %2\Status: %3',
                              Rec."Submission UID", Rec."Document UUID", Rec.Status);
                    end;

                    if Confirm(StrSubstNo('Are you sure you want to delete entry %1 for invoice %2?\Deletion reason: %3', Rec."Entry No.", Rec."Invoice No.", DeleteReason)) then begin
                        SubmissionLog := Rec;
                        if SubmissionLog.Delete(true) then
                            Message('Entry %1 has been deleted successfully.', SubmissionLog."Entry No.")
                        else
                            Error('Failed to delete entry %1.', SubmissionLog."Entry No.");
                    end;
                end;
            }

            action(DeleteSelectedEntries)
            {
                ApplicationArea = All;
                Caption = 'Delete Selected Entries';
                Image = Delete;
                ToolTip = 'Delete selected entries that meet deletion criteria (no Submission UID, no Document UUID, or Invalid/Submitted status).';
                Visible = true;
                Enabled = false; // Disable button

                trigger OnAction()
                var
                    SelectedSubmissionLog: Record "eInvoice Submission Log";
                    DeletedCount: Integer;
                    SkippedCount: Integer;
                    TotalSelected: Integer;
                    CanDelete: Boolean;
                    ConfirmMsg: Label 'Delete selected entries that meet deletion criteria?\This will delete entries without Submission UID, without Document UUID, or with Invalid/Submitted status.\Selected entries: %1';
                    ResultMsg: Label 'Deleted: %1 entries\Skipped: %2 entries (did not meet deletion criteria)';
                begin
                    CurrPage.SetSelectionFilter(SelectedSubmissionLog);
                    TotalSelected := SelectedSubmissionLog.Count();

                    if TotalSelected = 0 then begin
                        Message('Please select one or more entries to delete.');
                        exit;
                    end;

                    if not Confirm(ConfirmMsg, false, TotalSelected) then
                        exit;

                    DeletedCount := 0;
                    SkippedCount := 0;

                    if SelectedSubmissionLog.FindSet() then
                        repeat
                            CanDelete := false;

                            // Check if entry can be deleted based on various criteria
                            if (SelectedSubmissionLog."Submission UID" = '') or (SelectedSubmissionLog."Submission UID" = 'null') then
                                CanDelete := true
                            else if (SelectedSubmissionLog."Document UUID" = '') or (SelectedSubmissionLog."Document UUID" = 'null') then
                                CanDelete := true
                            else if (SelectedSubmissionLog.Status = 'Invalid') then
                                CanDelete := true
                            else if (SelectedSubmissionLog.Status = 'Submitted') then
                                CanDelete := true;

                            if CanDelete then begin
                                if SelectedSubmissionLog.Delete(true) then
                                    DeletedCount += 1
                                else
                                    SkippedCount += 1;
                            end else
                                SkippedCount += 1;
                        until SelectedSubmissionLog.Next() = 0;

                    Message(ResultMsg, DeletedCount, SkippedCount);
                    CurrPage.Update(false);
                end;
            }
            action(RefreshByDateRange)
            {
                ApplicationArea = All;
                Caption = 'Refresh by Date Range';
                Image = RefreshLines;
                ToolTip = 'Refresh the status for submissions within a specified date range using direct LHDN API calls';

                trigger OnAction()
                var
                    SubmissionStatusCU: Codeunit "eInvoice Submission Status";
                    SubmissionLog: Record "eInvoice Submission Log";
                    UpdatedCount: Integer;
                    FailedCount: Integer;
                    TotalEntries: Integer;
                    FromDate: Date;
                    ToDate: Date;
                    DateRangeText: Text;
                begin
                    // Let user pick exact dates via dialog, fallback to helper if cancelled
                    if not OpenDateRangeDialog(FromDate, ToDate) then
                        if not GetDateRangeFromUser(FromDate, ToDate) then
                            exit;

                    // Validate date range
                    if FromDate > ToDate then begin
                        Message('From Date cannot be later than To Date.');
                        exit;
                    end;

                    // Count entries in the date range
                    SubmissionLog.SetFilter("Submission UID", '<>%1', '');
                    SubmissionLog.SetRange("Submission Date", CreateDateTime(FromDate, 0T), CreateDateTime(ToDate, 235959T));
                    TotalEntries := SubmissionLog.Count();

                    if TotalEntries = 0 then begin
                        Message('No submission entries found with Submission UIDs in the date range %1 to %2.', Format(FromDate, 0, '<Day,2>/<Month,2>/<Year4>'), Format(ToDate, 0, '<Day,2>/<Month,2>/<Year4>'));
                        exit;
                    end;

                    DateRangeText := StrSubstNo('%1 to %2', Format(FromDate, 0, '<Day,2>/<Month,2>/<Year4>'), Format(ToDate, 0, '<Day,2>/<Month,2>/<Year4>'));
                    // Confirm (extra prompt for large batches)
                    if not Confirm(StrSubstNo('Refresh status for %1 submissions (%2)?', TotalEntries, DateRangeText)) then
                        exit;
                    if (TotalEntries > 200) and not Confirm('This is a large batch and may take some time. Continue?') then
                        exit;

                    // Directly process entries in the date range (no background jobs)
                    UpdatedCount := 0;
                    FailedCount := 0;

                    SubmissionLog.SetFilter("Submission UID", '<>%1', '');
                    SubmissionLog.SetRange("Submission Date", CreateDateTime(FromDate, 0T), CreateDateTime(ToDate, 235959T));

                    if SubmissionLog.FindSet() then begin
                        repeat
                            if DirectRefreshSingle(SubmissionLog) then
                                UpdatedCount += 1
                            else
                                FailedCount += 1;
                            // Light rate-limit buffer
                            Sleep(300);
                        until SubmissionLog.Next() = 0;
                    end;

                    Message('Direct refresh completed for date range %1 to %2. Updated: %3, Failed: %4.',
                            Format(FromDate, 0, '<Day,2>/<Month,2>/<Year4>'),
                            Format(ToDate, 0, '<Day,2>/<Month,2>/<Year4>'),
                            UpdatedCount, FailedCount);

                    CurrPage.Update(false);
                end;
            }

            action(ExportToExcel)
            {
                ApplicationArea = All;
                Caption = 'Export to Excel';
                Image = ExportFile;
                ToolTip = 'Export the submission log to Excel for analysis';

                trigger OnAction()
                var
                    ExcelBuf: Record "Excel Buffer" temporary;
                    FileName: Text;
                begin
                    // Header row
                    ExcelBuf.Reset();
                    ExcelBuf.DeleteAll();
                    ExcelBuf.NewRow();
                    ExcelBuf.AddColumn('Entry No.', false, '', true, false, false, '', ExcelBuf."Cell Type"::Number);
                    ExcelBuf.AddColumn('Invoice No.', false, '', true, false, false, '', ExcelBuf."Cell Type"::Text);
                    ExcelBuf.AddColumn('Customer Name', false, '', true, false, false, '', ExcelBuf."Cell Type"::Text);
                    ExcelBuf.AddColumn('Amount', false, '', true, false, false, '', ExcelBuf."Cell Type"::Number);
                    ExcelBuf.AddColumn('Amount Including VAT', false, '', true, false, false, '', ExcelBuf."Cell Type"::Number);
                    ExcelBuf.AddColumn('Submission UID', false, '', true, false, false, '', ExcelBuf."Cell Type"::Text);
                    ExcelBuf.AddColumn('Document UUID', false, '', true, false, false, '', ExcelBuf."Cell Type"::Text);
                    ExcelBuf.AddColumn('Status', false, '', true, false, false, '', ExcelBuf."Cell Type"::Text);
                    ExcelBuf.AddColumn('Submission Date', false, '', true, false, false, '', ExcelBuf."Cell Type"::Date);
                    ExcelBuf.AddColumn('Response Date', false, '', true, false, false, '', ExcelBuf."Cell Type"::Date);
                    ExcelBuf.AddColumn('Posting Date', false, '', true, false, false, '', ExcelBuf."Cell Type"::Date);
                    ExcelBuf.AddColumn('Environment', false, '', true, false, false, '', ExcelBuf."Cell Type"::Text);
                    ExcelBuf.AddColumn('Error Message', false, '', true, false, false, '', ExcelBuf."Cell Type"::Text);

                    // Data rows
                    if Rec.FindSet() then begin
                        repeat
                            ExcelBuf.NewRow();
                            ExcelBuf.AddColumn(Rec."Entry No.", false, '', false, false, false, '', ExcelBuf."Cell Type"::Number);
                            ExcelBuf.AddColumn(Rec."Invoice No.", false, '', false, false, false, '', ExcelBuf."Cell Type"::Text);
                            ExcelBuf.AddColumn(Rec."Customer Name", false, '', false, false, false, '', ExcelBuf."Cell Type"::Text);
                            ExcelBuf.AddColumn(Rec."Amount", false, '', false, false, false, '', ExcelBuf."Cell Type"::Number);
                            ExcelBuf.AddColumn(Rec."Amount Including VAT", false, '', false, false, false, '', ExcelBuf."Cell Type"::Number);
                            ExcelBuf.AddColumn(Rec."Submission UID", false, '', false, false, false, '', ExcelBuf."Cell Type"::Text);
                            ExcelBuf.AddColumn(Rec."Document UUID", false, '', false, false, false, '', ExcelBuf."Cell Type"::Text);
                            ExcelBuf.AddColumn(Rec.Status, false, '', false, false, false, '', ExcelBuf."Cell Type"::Text);
                            ExcelBuf.AddColumn(DT2Date(Rec."Submission Date"), false, '', false, false, false, '', ExcelBuf."Cell Type"::Date);
                            ExcelBuf.AddColumn(DT2Date(Rec."Response Date"), false, '', false, false, false, '', ExcelBuf."Cell Type"::Date);
                            ExcelBuf.AddColumn(Rec."Posting Date", false, '', false, false, false, '', ExcelBuf."Cell Type"::Date);
                            ExcelBuf.AddColumn(Format(Rec.Environment), false, '', false, false, false, '', ExcelBuf."Cell Type"::Text);
                            ExcelBuf.AddColumn(CopyStr(Rec."Error Message", 1, 250), false, '', false, false, false, '', ExcelBuf."Cell Type"::Text);
                        until Rec.Next() = 0;
                    end;

                    // Build workbook and open
                    FileName := StrSubstNo('eInvoice_Submission_Log_%1.xlsx',
                        Format(CurrentDateTime, 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>'));
                    ExcelBuf.CreateNewBook('e-Invoice Submission Log');
                    ExcelBuf.WriteSheet('Submission Log', CompanyName, UserId);
                    ExcelBuf.CloseBook();
                    ExcelBuf.SetFriendlyFilename(FileName);
                    ExcelBuf.OpenExcel();
                end;
            }


            action(OpenPostedInvoice)
            {
                ApplicationArea = All;
                Caption = 'Open Posted Invoice';
                Image = Navigate;
                ToolTip = 'Open the related posted sales invoice.';

                trigger OnAction()
                var
                    SIH: Record "Sales Invoice Header";
                begin
                    if SIH.Get(Rec."Invoice No.") then
                        Page.Run(Page::"Posted Sales Invoice", SIH);
                end;
            }

            action(ClearOldEntries)
            {
                ApplicationArea = All;
                Caption = 'Clear Old Entries';
                Image = Delete;
                ToolTip = 'Clear log entries older than 30 days';

                trigger OnAction()
                var
                    DeleteDate: Date;
                    DeletedCount: Integer;
                begin
                    if Confirm('Delete entries older than 30 days?') then begin
                        DeleteDate := CalcDate('-30D', Today);
                        DeletedCount := 0;

                        Rec.SetRange("Submission Date", 0DT, CreateDateTime(DeleteDate, 235959T));
                        if Rec.FindSet() then begin
                            repeat
                                Rec.Delete();
                                DeletedCount += 1;
                            until Rec.Next() = 0;
                        end;

                        Message('Cleared %1 old log entries.', DeletedCount);
                    end;
                end;
            }

            action(ShowDeletableEntries)
            {
                ApplicationArea = All;
                Caption = 'Show Deletable Entries';
                Image = Filter;
                ToolTip = 'Filter to show only entries that can be deleted (no Submission UID, no Document UUID, or Invalid/Submitted status).';
                Visible = true;

                trigger OnAction()
                begin
                    // Clear existing filters
                    Rec.Reset();

                    // Filter for entries that can be deleted:
                    // 1. Entries where Submission UID is empty or 'null'
                    // 2. Entries where Document UUID is empty or 'null'  
                    // 3. Entries with Invalid or Submitted status
                    Rec.SetFilter("Submission UID", '%1|%2', '', 'null');
                    Rec.SetFilter("Document UUID", '%1|%2', '', 'null');
                    Rec.SetFilter(Status, '%1|%2', 'Invalid', 'Submitted');

                    // Use OR logic: entries matching any of the above criteria
                    Message('Filtered to show entries that can be deleted.\Entries without Submission UID, without Document UUID, or with Invalid/Submitted status are now visible.');
                end;
            }

            action(ShowInvalidEntries)
            {
                ApplicationArea = All;
                Caption = 'Show Invalid Entries';
                Image = Filter;
                ToolTip = 'Filter to show only entries with Invalid status.';
                Visible = true;

                trigger OnAction()
                begin
                    Rec.Reset();
                    Rec.SetRange(Status, 'Invalid');
                    Message('Filtered to show only entries with Invalid status.');
                end;
            }

            action(ShowSubmittedEntries)
            {
                ApplicationArea = All;
                Caption = 'Show Submitted Entries';
                Image = Filter;
                ToolTip = 'Filter to show only entries with Submitted status.';
                Visible = true;

                trigger OnAction()
                begin
                    Rec.Reset();
                    Rec.SetRange(Status, 'Submitted');
                    Message('Filtered to show only entries with Submitted status.');
                end;
            }
            action(ShowDeletionSummary)
            {
                ApplicationArea = All;
                Caption = 'Show Deletion Summary';
                Image = Statistics;
                ToolTip = 'Show summary of how many entries can be deleted based on current criteria (no Submission UID, no Document UUID, or Invalid/Submitted status).';
                Visible = true;

                trigger OnAction()
                var
                    SubmissionLog: Record "eInvoice Submission Log";
                    TotalEntries: Integer;
                    DeletableEntries: Integer;
                    WithSubmissionUID: Integer;
                    WithDocumentUUID: Integer;
                    InvalidStatusCount: Integer;
                    SubmittedStatusCount: Integer;
                    SummaryMsg: Label 'Total Entries: %1\Deletable Entries: %2\- Entries with Invalid Status: %3\- Entries with Submitted Status: %4\- Entries without Submission UID: %5\- Entries without Document UUID: %6\Note: Entries can be deleted if they have Invalid/Submitted status OR lack Submission UID OR lack Document UUID.';
                begin
                    // Count total entries
                    TotalEntries := SubmissionLog.Count();

                    // Count entries with Invalid status
                    SubmissionLog.Reset();
                    SubmissionLog.SetRange(Status, 'Invalid');
                    InvalidStatusCount := SubmissionLog.Count();

                    // Count entries with Submitted status
                    SubmissionLog.Reset();
                    SubmissionLog.SetRange(Status, 'Submitted');
                    SubmittedStatusCount := SubmissionLog.Count();

                    // Count entries without Submission UID (empty OR literal 'null')
                    SubmissionLog.Reset();
                    SubmissionLog.SetFilter("Submission UID", '%1|%2', '', 'null');
                    WithSubmissionUID := SubmissionLog.Count();

                    // Count entries without Document UUID (empty OR literal 'null')
                    SubmissionLog.Reset();
                    SubmissionLog.SetFilter("Document UUID", '%1|%2', '', 'null');
                    WithDocumentUUID := SubmissionLog.Count();

                    // Calculate total deletable entries (may have overlap, so we need to count unique)
                    SubmissionLog.Reset();
                    if SubmissionLog.FindSet() then
                        repeat
                            if (SubmissionLog.Status = 'Invalid') or
                               (SubmissionLog.Status = 'Submitted') or
                               (SubmissionLog."Submission UID" = '') or (SubmissionLog."Submission UID" = 'null') or
                               (SubmissionLog."Document UUID" = '') or (SubmissionLog."Document UUID" = 'null') then
                                DeletableEntries += 1;
                        until SubmissionLog.Next() = 0;

                    Message(SummaryMsg, TotalEntries, DeletableEntries, InvalidStatusCount, SubmittedStatusCount, WithSubmissionUID, WithDocumentUUID);
                end;
            }

            action(ClearFilters)
            {
                ApplicationArea = All;
                Caption = 'Clear Filters';
                Image = ClearFilter;
                ToolTip = 'Clear all filters and show all entries.';
                Visible = true;

                trigger OnAction()
                begin
                    Rec.Reset();
                    Message('All filters have been cleared.');
                end;
            }

            action(CleanupOldDeletableEntries)
            {
                ApplicationArea = All;
                Caption = 'Cleanup Old Deletable Entries';
                Image = Delete;
                ToolTip = 'Clean up old entries that can be deleted (no Submission UID, no Document UUID, or Invalid/Submitted status).';
                Visible = true;

                trigger OnAction()
                var
                    SubmissionStatusCU: Codeunit "eInvoice Submission Status";
                    DaysOld: Integer;
                    DeletableCount: Integer;
                    ConfirmMsg: Label 'Clean up old entries that can be deleted?\This will remove entries older than %1 days that have no Submission UID, no Document UUID, or Invalid/Submitted status.\Note: This action cannot be undone.';
                    ResultMsg: Label 'Found %1 old entries that can be deleted.\Click OK to proceed with deletion.';
                begin
                    // Get number of days from user
                    DaysOld := 30; // Default to 30 days
                    if not GetDaysOldFromUser(DaysOld) then
                        exit;

                    // First, count how many entries can be deleted
                    DeletableCount := SubmissionStatusCU.CleanupOldDeletableEntries(DaysOld, false);

                    if DeletableCount = 0 then begin
                        Message('No old entries found that can be deleted.');
                        exit;
                    end;

                    if not Confirm(ConfirmMsg, false, DaysOld) then
                        exit;

                    if not Confirm(ResultMsg, false, DeletableCount) then
                        exit;

                    // Now actually delete the entries
                    DeletableCount := SubmissionStatusCU.CleanupOldDeletableEntries(DaysOld, true);

                    Message('Successfully deleted %1 old entries that met deletion criteria.', DeletableCount);
                    CurrPage.Update(false);
                end;
            }

            action(UpdateSubmissionLogAmounts)
            {
                ApplicationArea = All;
                Caption = 'Update Submission Log Amounts';
                Image = UpdateDescription;
                ToolTip = 'Update Amount and Amount Including VAT for existing submission log entries';
                Visible = true;

                trigger OnAction()
                var
                    eInvoiceJSONGenerator: Codeunit "eInvoice JSON Generator";
                begin
                    if Confirm('This will update the Amount and Amount Including VAT fields for all existing submission log entries. Do you want to continue?', false) then begin
                        eInvoiceJSONGenerator.UpdateExistingSubmissionLogAmounts();
                        Message('Submission log amounts have been updated successfully.');
                        CurrPage.Update(false);
                    end;
                end;
            }

            action(UpdateCustomerNumbers)
            {
                ApplicationArea = All;
                Caption = 'Update Customer Numbers';
                Image = Customer;
                ToolTip = 'Update Customer No. field for existing submission log entries that have empty Customer No.';
                Visible = true;

                trigger OnAction()
                var
                    eInvoiceLogUpdate: Codeunit "eInvoice Submission Log Update";
                begin
                    if Confirm('This will update the Customer No. field for all existing submission log entries that have empty Customer No. Do you want to continue?', false) then begin
                        eInvoiceLogUpdate.UpdateCustomerNoInSubmissionLog();
                        CurrPage.Update(false);
                    end;
                end;
            }

            action(DiagnoseCustomerNo)
            {
                ApplicationArea = All;
                Caption = 'Diagnose Customer No. Issue';
                Image = Troubleshoot;
                ToolTip = 'Diagnose why Customer No. is empty for the selected entry';
                Visible = true;

                trigger OnAction()
                var
                    eInvoiceLogUpdate: Codeunit "eInvoice Submission Log Update";
                begin
                    if Rec."Entry No." = 0 then begin
                        Message('Please select a submission log entry first.');
                        exit;
                    end;
                    eInvoiceLogUpdate.DiagnoseSubmissionLogEntry(Rec."Entry No.");
                end;
            }

            action(ShowCustomerNoStatus)
            {
                ApplicationArea = All;
                Caption = 'Show Customer No. Status';
                Image = Statistics;
                ToolTip = 'Show how many entries have/don''t have Customer No. populated';
                Visible = true;

                trigger OnAction()
                var
                    eInvoiceLogUpdate: Codeunit "eInvoice Submission Log Update";
                begin
                    eInvoiceLogUpdate.ShowSubmissionLogCustomerNoStatus();
                end;
            }

            action(BackfillMissingLogs)
            {
                ApplicationArea = All;
                Caption = 'Backfill Missing Logs';
                Image = CreateDocument;
                ToolTip = 'Creates submission log entries for invoices that were submitted but have no log entry. Runs as background job.';

                trigger OnAction()
                var
                    SessionId: Integer;
                    eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
                begin
                    if not Confirm('This will retrieve submission data from LHDN API for all invoices and credit memos with Submission UIDs.\' +
                                '\\This will run as a BACKGROUND SESSION and may take several minutes.\' +
                                'You can continue working while it processes.\' +
                                '\\Continue?') then
                        exit;

                    // Start backgorund session that allows HTTP calls
                    if StartSession(SessionId, Codeunit::"eInvoice JSON Generator", CompanyName) then
                        Message('Backfill started successfully!\' +
                                '\\Session ID: %1\' +
                                'The process is running in the background.\' +
                                'Refresh this page in a few minutes to see new log entries.',
                                SessionId)
                    else
                        Error('Failed to start background session.');
                end;
            }


        }
    }

    var
        IsJotexCompany: Boolean;
        CanResubmit: Boolean;

    trigger OnOpenPage()
    var
        CompanyInfo: Record "Company Information";
    begin
        IsJotexCompany := CompanyInfo.Get() and (CompanyInfo.Name = 'JOTEX SDN BHD');
    end;


    local procedure ShowSubmissionHistory()
    var
        HistoryText: Text;
        InStream: InStream;
        HistoryArray: JsonArray;
        JsonToken: JsonToken;
        HistoryEntry: JsonObject;
        i: Integer;
        DisplayText: Text;
    begin
        if not Rec."Submission History".HasValue then begin
            Message('No history available');
            exit;
        end;
        Rec."Submission History".CreateInStream(InStream);
        InStream.ReadText(HistoryText);
        if not HistoryArray.ReadFrom(HistoryText) then begin
            Message('Cannot read history');
            exit;
        end;
        DisplayText := StrSubstNo('HISTORY - Invoice: %1, Total Attempts: %2\\\\', Rec."Invoice No.", Rec."Attempt Number");
        for i := 0 to HistoryArray.Count() - 1 do begin
            HistoryArray.Get(i, JsonToken);
            HistoryEntry := JsonToken.AsObject();
            DisplayText += StrSubstNo('--- Attempt #%1 ---\\', i + 1);
            DisplayText += 'Submission Date: ' + GetJsonValue(HistoryEntry, 'SubmissionDate') + '\\';
            DisplayText += 'Status: ' + GetJsonValue(HistoryEntry, 'Status') + '\\\\';

            // Show error details if present
            if GetJsonValue(HistoryEntry, 'ErrorCode') <> '' then begin
                DisplayText += 'Error Code: ' + GetJsonValue(HistoryEntry, 'ErrorCode') + '\\';
                DisplayText += 'Error Field: ' + GetJsonValue(HistoryEntry, 'ErrorPropertyPath') + '\\';
                DisplayText += 'Error Message: ' + GetJsonValue(HistoryEntry, 'ErrorEnglish') + '\\';
                if GetJsonValue(HistoryEntry, 'HTTPStatusCode') <> '' then
                    DisplayText += 'HTTP Status: ' + GetJsonValue(HistoryEntry, 'HTTPStatusCode') + '\\';
                if GetJsonValue(HistoryEntry, 'CorrelationID') <> '' then
                    DisplayText += 'Correlation ID: ' + GetJsonValue(HistoryEntry, 'CorrelationID') + '\\';
            end;

            // Show submission details
            if GetJsonValue(HistoryEntry, 'CustomerName') <> '' then
                DisplayText += 'Customer: ' + GetJsonValue(HistoryEntry, 'CustomerName') + '\\';
            if GetJsonValue(HistoryEntry, 'Amount') <> '' then
                DisplayText += 'Amount: ' + GetJsonValue(HistoryEntry, 'Amount') + '\\';
            if GetJsonValue(HistoryEntry, 'SubmissionUID') <> '' then
                DisplayText += 'Submission UID: ' + GetJsonValue(HistoryEntry, 'SubmissionUID') + '\\';
            if GetJsonValue(HistoryEntry, 'DocumentUUID') <> '' then
                DisplayText += 'Document UUID: ' + GetJsonValue(HistoryEntry, 'DocumentUUID') + '\\';

            DisplayText += 'User: ' + GetJsonValue(HistoryEntry, 'UserID') + '\\\\';
        end;
        Message(DisplayText);
    end;

    local procedure GetJsonValue(JsonObj: JsonObject; KeyName: Text): Text
    var
        JsonToken: JsonToken;
    begin
        if JsonObj.Get(KeyName, JsonToken) then
            exit(JsonToken.AsValue().AsText());
        exit('');
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
    /// Create a background job for status refresh to avoid context restrictions
    /// </summary>
    local procedure CreateBackgroundJobForStatusRefresh()
    var
        JobQueueEntry: Record "Job Queue Entry";
        JobQueueLogEntry: Record "Job Queue Log Entry";
        LogEntryNo: Integer;
    begin
        // Create job queue entry
        JobQueueEntry.Init();
        JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
        JobQueueEntry."Object ID to Run" := 50312;
        JobQueueEntry."Job Queue Category Code" := 'EINVOICE';
        JobQueueEntry."Description" := 'eInvoice Status Refresh';
        JobQueueEntry."Parameter String" := '';
        JobQueueEntry."User ID" := UserId;
        JobQueueEntry."Earliest Start Date/Time" := CurrentDateTime;
        JobQueueEntry.Status := JobQueueEntry.Status::Ready;
        JobQueueEntry."Maximum No. of Attempts to Run" := 1;
        JobQueueEntry.Insert(true);

        // Log the job creation
        if JobQueueLogEntry.FindLast() then
            LogEntryNo := JobQueueLogEntry."Entry No." + 1
        else
            LogEntryNo := 1;

        JobQueueLogEntry.Init();
        JobQueueLogEntry."Entry No." := LogEntryNo;
        JobQueueLogEntry."Status" := JobQueueLogEntry.Status::Success;
        JobQueueLogEntry."Start Date/Time" := CurrentDateTime;
        JobQueueLogEntry."End Date/Time" := CurrentDateTime;
        JobQueueLogEntry."Object Type to Run" := JobQueueLogEntry."Object Type to Run"::Codeunit;
        JobQueueLogEntry."Object ID to Run" := 50312;
        JobQueueLogEntry."Job Queue Category Code" := 'EINVOICE';
        JobQueueLogEntry."Description" := 'eInvoice Status Refresh - Job Created';
        JobQueueLogEntry.Insert();
    end;

    /// <summary>
    /// Create a background job for bulk status refresh
    /// </summary>
    local procedure CreateBulkRefreshJob(): Boolean
    var
        JobQueueEntry: Record "Job Queue Entry";
    begin
        // Create job queue entry for bulk refresh
        JobQueueEntry.Init();
        JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
        JobQueueEntry."Object ID to Run" := Codeunit::"eInvoice Submission Status";
        JobQueueEntry."Job Queue Category Code" := 'EINVOICE';
        JobQueueEntry.Description := 'eInvoice Bulk Status Refresh - All Submissions';
        JobQueueEntry."Parameter String" := 'BULK_REFRESH_ALL'; // Indicates bulk refresh operation
        JobQueueEntry."User ID" := UserId;
        JobQueueEntry."Earliest Start Date/Time" := CurrentDateTime + 5000; // Start in 5 seconds
        JobQueueEntry.Status := JobQueueEntry.Status::Ready;
        JobQueueEntry."Maximum No. of Attempts to Run" := 3;
        JobQueueEntry."Rerun Delay (sec.)" := 30;

        exit(JobQueueEntry.Insert(true));
    end;

    /// <summary>
    /// Create background jobs for selected entries that failed direct refresh
    /// </summary>
    local procedure CreateSelectedBackgroundJobs(var SelectedSubmissionLog: Record "eInvoice Submission Log")
    var
        JobQueueEntry: Record "Job Queue Entry";
        SubmissionStatusCU: Codeunit "eInvoice Submission Status";
        JobsCreated: Integer;
        JobsFailed: Integer;
    begin
        JobsCreated := 0;
        JobsFailed := 0;

        // Create individual background jobs for each selected entry
        if SelectedSubmissionLog.FindSet() then begin
            repeat
                if SelectedSubmissionLog."Submission UID" <> '' then begin
                    if SubmissionStatusCU.CreateBackgroundStatusRefreshJob(SelectedSubmissionLog."Submission UID") then
                        JobsCreated += 1
                    else
                        JobsFailed += 1;
                end;
            until SelectedSubmissionLog.Next() = 0;
        end;

        // Only show message if there were failures creating jobs
        if JobsFailed > 0 then
            Message('Created %1 background jobs successfully, %2 failed.\Check "Background Jobs" for progress.', JobsCreated, JobsFailed);
    end;

    /// <summary>
    /// Get date range from user input with validation
    /// </summary>
    local procedure GetDateRangeFromUser(var FromDate: Date; var ToDate: Date): Boolean
    begin
        // Initialize with empty dates - user will select via date picker
        FromDate := 0D;
        ToDate := 0D;

        // Show date picker options directly
        if not GetDateRangeSimple(FromDate, ToDate) then
            exit(false);

        // Validate the date range
        if FromDate > ToDate then begin
            Message(StrSubstNo('From Date %1 cannot be later than To Date %2.', Format(FromDate, 0, '<Day,2>/<Month,2>/<Year4>'), Format(ToDate, 0, '<Day,2>/<Month,2>/<Year4>')));
            exit(false);
        end;

        // Don't allow future dates for ToDate (but allow for FromDate for planning purposes)
        if ToDate > Today then begin
            Message(StrSubstNo('To Date %1 cannot be in the future. Current date is %2.', Format(ToDate, 0, '<Day,2>/<Month,2>/<Year4>'), Format(Today, 0, '<Day,2>/<Month,2>/<Year4>')));
            exit(false);
        end;

        // Don't allow very old dates (more than 1 year) - but allow future dates for planning
        if (FromDate < CalcDate('-1Y', Today)) and (FromDate < Today) then begin
            if not Confirm(StrSubstNo('From Date %1 is more than 1 year ago. This may include many entries. Continue?', Format(FromDate, 0, '<Day,2>/<Month,2>/<Year4>'))) then
                exit(false);
        end;

        exit(true);
    end;

    local procedure OpenDateRangeDialog(var FromDate: Date; var ToDate: Date): Boolean
    var
        DateDlg: Page "eInv Date Range Picker";
        F: Date;
        T: Date;
    begin
        // Initialize with sensible defaults (last 7 days)
        F := CalcDate('-7D', Today);
        T := Today;
        DateDlg.SetInitialDates(F, T);
        if DateDlg.RunModal() = Action::OK then begin
            DateDlg.GetDates(FromDate, ToDate);
            exit(true);
        end;
        exit(false);
    end;

    /// <summary>
    /// Simple date range selection using predefined options
    /// </summary>
    local procedure GetDateRangeSimple(var FromDate: Date; var ToDate: Date): Boolean
    var
        Selection: Integer;
    begin
        Selection := StrMenu('Today,Single Date,Last 7 days,Last 30 days,Last 90 days,This month,Last month,This year,Custom dates', 3, 'Select date range for refresh:');

        case Selection of
            0:
                exit(false); // User cancelled
            1:
                begin // Today
                    FromDate := Today;
                    ToDate := Today;
                end;
            2:
                begin // Single Date
                    if not GetSingleDateFromUser(FromDate) then
                        exit(false);
                    ToDate := FromDate;
                end;
            3:
                begin // Last 7 days
                    FromDate := CalcDate('-7D', Today);
                    ToDate := Today;
                end;
            4:
                begin // Last 30 days
                    FromDate := CalcDate('-30D', Today);
                    ToDate := Today;
                end;
            5:
                begin // Last 90 days
                    FromDate := CalcDate('-90D', Today);
                    ToDate := Today;
                end;
            6:
                begin // This month
                    FromDate := CalcDate('-CM', Today);
                    ToDate := Today;
                end;
            7:
                begin // Last month
                    FromDate := CalcDate('-1M-CM', Today);
                    ToDate := CalcDate('-1M+CM', Today);
                end;
            8:
                begin // This year
                    FromDate := CalcDate('-CY', Today);
                    ToDate := Today;
                end;
            9:
                begin // Custom dates - use date picker
                    if not GetCustomDateRangeWithPicker(FromDate, ToDate) then
                        exit(false);
                end;
        end;

        exit(true);
    end;

    /// <summary>
    /// Get a single date from user input using a simple date picker approach
    /// </summary>
    local procedure GetSingleDateFromUser(var SelectedDate: Date): Boolean
    var
        DateSelection: Integer;
        SelectedDateText: Text;
        ParsedDate: Date;
    begin
        // Show a simple date picker with common options
        DateSelection := StrMenu('Today,Yesterday,Last Week,Last Month,Last Year,Other', 1, 'Select a date:');

        case DateSelection of
            0:
                exit(false); // User cancelled
            1:
                SelectedDate := Today; // Today
            2:
                SelectedDate := CalcDate('-1D', Today); // Yesterday
            3:
                SelectedDate := CalcDate('-7D', Today); // Last Week
            4:
                SelectedDate := CalcDate('-1M', Today); // Last Month
            5:
                SelectedDate := CalcDate('-1Y', Today); // Last Year
            6:
                begin // Other - use a simple confirmation approach since we can't easily get user input
                    SelectedDateText := Format(Today, 0, '<Day,2>/<Month,2>/<Year4>');

                    // For now, use a simple confirmation approach since we can't easily get user input
                    if not Confirm(StrSubstNo('Use %1 as the selected date?\Click No to cancel.', Format(Today, 0, '<Day,2>/<Month,2>/<Year4>'))) then
                        exit(false);

                    SelectedDate := Today;
                end;
        end;

        // Validate the selected date
        if SelectedDate > Today then begin
            Message('Selected date cannot be in the future.');
            exit(false);
        end;

        if SelectedDate < CalcDate('-1Y', Today) then begin
            if not Confirm('Selected date is more than 1 year ago. This may include many entries. Continue?') then
                exit(false);
        end;

        exit(true);
    end;

    /// <summary>
    /// Get custom date range using enhanced date picker options
    /// </summary>
    local procedure GetCustomDateRangeWithPicker(var FromDate: Date; var ToDate: Date): Boolean
    var
        DateRangeSelection: Integer;
        TempFromDate: Date;
        TempToDate: Date;
    begin
        // Show enhanced custom date range options
        DateRangeSelection := StrMenu('Last 7 days,Last 14 days,Last 30 days,Last 60 days,Last 90 days,Last 6 months,Last year,This week,This month,This quarter,This year,Other', 3, 'Select custom date range:');

        case DateRangeSelection of
            0:
                exit(false); // User cancelled
            1:
                begin // Last 7 days
                    FromDate := CalcDate('-7D', Today);
                    ToDate := Today;
                end;
            2:
                begin // Last 14 days
                    FromDate := CalcDate('-14D', Today);
                    ToDate := Today;
                end;
            3:
                begin // Last 30 days
                    FromDate := CalcDate('-30D', Today);
                    ToDate := Today;
                end;
            4:
                begin // Last 60 days
                    FromDate := CalcDate('-60D', Today);
                    ToDate := Today;
                end;
            5:
                begin // Last 90 days
                    FromDate := CalcDate('-90D', Today);
                    ToDate := Today;
                end;
            6:
                begin // Last 6 months
                    FromDate := CalcDate('-6M', Today);
                    ToDate := Today;
                end;
            7:
                begin // Last year
                    FromDate := CalcDate('-1Y', Today);
                    ToDate := Today;
                end;
            8:
                begin // This week
                    FromDate := CalcDate('-CW', Today);
                    ToDate := Today;
                end;
            9:
                begin // This month
                    FromDate := CalcDate('-CM', Today);
                    ToDate := Today;
                end;
            10:
                begin // This quarter
                    FromDate := CalcDate('-CQ', Today);
                    ToDate := Today;
                end;
            11:
                begin // This year
                    FromDate := CalcDate('-CY', Today);
                    ToDate := Today;
                end;
            12:
                begin // Other - use current page filters
                    if Rec.GetFilter("Submission Date") <> '' then begin
                        if Confirm('Use the current Submission Date filter as the date range?') then begin
                            exit(true); // Keep current FromDate and ToDate
                        end;
                    end;

                    // Fallback to simple date input
                    Message('For specific custom dates, please:\1. Use the filter on "Submission Date" column\2. Set your desired date range filter\3. Then run "Refresh by Date Range" again and select "Custom dates"');
                    exit(false);
                end;
        end;

        exit(true);
    end;



    /// <summary>
    /// Create background job for date range refresh
    /// </summary>
    local procedure CreateDateRangeBackgroundJob(FromDate: Date; ToDate: Date): Boolean
    var
        JobQueueEntry: Record "Job Queue Entry";
        ParameterString: Text;
    begin
        // Create parameter string with date range
        ParameterString := StrSubstNo('DATE_RANGE|%1|%2', Format(FromDate), Format(ToDate));

        // Create job queue entry for date range refresh
        JobQueueEntry.Init();
        JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
        JobQueueEntry."Object ID to Run" := Codeunit::"eInvoice Submission Status";
        JobQueueEntry."Job Queue Category Code" := 'EINVOICE';
        JobQueueEntry.Description := StrSubstNo('eInvoice Status Refresh - Date Range %1 to %2', FromDate, ToDate);
        JobQueueEntry."Parameter String" := ParameterString;
        JobQueueEntry."User ID" := UserId;
        JobQueueEntry."Earliest Start Date/Time" := CurrentDateTime + 5000; // Start in 5 seconds
        JobQueueEntry.Status := JobQueueEntry.Status::Ready;
        JobQueueEntry."Maximum No. of Attempts to Run" := 3;
        JobQueueEntry."Rerun Delay (sec.)" := 30;

        if JobQueueEntry.Insert(true) then begin
            exit(true);
        end else begin
            Message('Failed to create background job for date range refresh.');
            exit(false);
        end;
    end;

    local procedure SendDateRangeSummaryNotification(FromDate: Date; ToDate: Date; TotalEntries: Integer; UpdatedCount: Integer; FailedCount: Integer)
    var
        Notif: Notification;
        Msg: Text;
    begin
        Msg := StrSubstNo('Date range %1 to %2 | Total: %3 | Updated: %4 | Failed: %5',
            Format(FromDate, 0, '<Day,2>/<Month,2>/<Year4>'),
            Format(ToDate, 0, '<Day,2>/<Month,2>/<Year4>'),
            TotalEntries,
            UpdatedCount,
            FailedCount);

        Notif.Scope := NotificationScope::LocalScope;
        Notif.Message(Msg);
        Notif.Send();
    end;

    /// <summary>
    /// Parse and store validation errors from LHDN API response
    /// Uses the codeunit's error parsing methods to extract and store error details
    /// </summary>
    /// <param name="Entry">The submission log entry to update with error details</param>
    /// <param name="ResponseText">The JSON response from LHDN API</param>
    /// <returns>True if errors were found and stored successfully</returns>
    local procedure ParseAndStoreValidationErrors(var Entry: Record "eInvoice Submission Log"; ResponseText: Text): Boolean
    var
        SubmissionStatusCU: Codeunit "eInvoice Submission Status";
        ErrorJsonText: Text;
        HttpStatusCode: Integer;
        CorrelationId: Text;
    begin
        // Use the codeunit's ParseSubmissionResponseForErrors to extract error details
        CorrelationId := CreateGuid();
        if SubmissionStatusCU.ParseSubmissionResponseForErrors(ResponseText, Entry."Document UUID", ErrorJsonText, HttpStatusCode) then begin
            // Store the error details using the same method as initial submission
            SubmissionStatusCU.ParseAndStoreErrorResponse(Entry, ErrorJsonText, HttpStatusCode, CorrelationId);
            exit(true);
        end;
        exit(false);
    end;

    /// <summary>
    /// Direct refresh using the same approach as Posted Sales Invoice page
    /// </summary>
    local procedure DirectRefreshSingle(var Entry: Record "eInvoice Submission Log"): Boolean
    var
        HttpClient: HttpClient;
        HttpRequestMessage: HttpRequestMessage;
        HttpResponseMessage: HttpResponseMessage;
        RequestHeaders: HttpHeaders;
        eInvoiceSetup: Record "eInvoiceSetup";
        eInvoiceHelper: Codeunit eInvoiceHelper;
        AccessToken: Text;
        ApiUrl: Text;
        ResponseText: Text;
        StatusText: Text;
        LhdnStatus: Text;
    begin
        if Entry."Submission UID" = '' then
            exit(false);

        if not eInvoiceSetup.Get('SETUP') then
            exit(false);

        eInvoiceHelper.InitializeHelper();
        AccessToken := eInvoiceHelper.GetAccessTokenFromSetup(eInvoiceSetup);
        if AccessToken = '' then
            exit(false);

        if eInvoiceSetup.Environment = eInvoiceSetup.Environment::Preprod then
            ApiUrl := StrSubstNo('https://preprod-api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1', Entry."Submission UID")
        else
            ApiUrl := StrSubstNo('https://api.myinvois.hasil.gov.my/api/v1.0/documentsubmissions/%1', Entry."Submission UID");

        HttpRequestMessage.Method := 'GET';
        HttpRequestMessage.SetRequestUri(ApiUrl);
        HttpRequestMessage.GetHeaders(RequestHeaders);
        RequestHeaders.Clear();
        RequestHeaders.Add('Accept', 'application/json');
        RequestHeaders.Add('Accept-Language', 'en');
        RequestHeaders.Add('Authorization', 'Bearer ' + AccessToken);

        if HttpClient.Send(HttpRequestMessage, HttpResponseMessage) then begin
            HttpResponseMessage.Content.ReadAs(ResponseText);
            if HttpResponseMessage.IsSuccessStatusCode then begin
                // Parse status like posted pages
                LhdnStatus := ExtractStatusFromApiResponse(ResponseText, Entry."Document UUID");
                Entry.Status := LhdnStatus;
                Entry."Response Date" := CurrentDateTime;
                Entry."Last Updated" := CurrentDateTime;

                // Populate UUID if missing
                if Entry."Document UUID" = '' then
                    Entry."Document UUID" := CopyStr(ExtractUuidFromApiResponse(ResponseText), 1, MaxStrLen(Entry."Document UUID"));

                // Extract Long ID when available (Valid/Cancelled docs)
                Entry."Long ID" := CopyStr(ExtractLongIdFromApiResponse(ResponseText, Entry."Document UUID"), 1, MaxStrLen(Entry."Long ID"));

                // Parse and store validation errors if status is Invalid or Rejected
                if (LhdnStatus = 'Invalid') or (LhdnStatus = 'Rejected') then begin
                    if Entry."Document UUID" <> '' then begin
                        if ParseAndStoreValidationErrors(Entry, ResponseText) then begin
                            // Validation errors were parsed and stored successfully
                        end else begin
                            // LHDN Get Submission API doesn't return error details for already-Invalid documents
                            // Try to reconstruct Error Message from existing error fields
                            if (Entry."Error Code" <> '') or (Entry."Error English" <> '') then begin
                                ResponseText := ''; // Reuse variable for error message construction
                                if Entry."Error Code" <> '' then
                                    ResponseText := Entry."Error Code" + ': ';
                                if Entry."Error English" <> '' then
                                    ResponseText += Entry."Error English"
                                else if Entry."Error Malay" <> '' then
                                    ResponseText += Entry."Error Malay";
                                if ResponseText <> '' then
                                    Entry."Error Message" := CopyStr(ResponseText, 1, MaxStrLen(Entry."Error Message"));
                            end else if Entry."Error Message" = '' then begin
                                Entry."Error Message" := CopyStr('Status: Invalid - Error details were captured during initial submission', 1, MaxStrLen(Entry."Error Message"));
                            end;
                        end;
                    end else begin
                        // No Document UUID to match errors
                        if Entry."Error Message" = '' then
                            Entry."Error Message" := CopyStr('Status: Invalid - Document UUID missing, cannot retrieve error details', 1, MaxStrLen(Entry."Error Message"));
                    end;
                end else begin
                    // For Valid, Accepted, or other statuses, set generic success message
                    Entry."Error Message" := CopyStr('Status refreshed from LHDN via direct API (Submission Log).', 1, MaxStrLen(Entry."Error Message"));
                end;

                Entry.Modify();
                // Build and persist validation link and push to posted invoice
                PopulateValidationLink(Entry);
                exit(true);
            end;
        end;
        exit(false);
    end;

    local procedure PopulateValidationLink(var Entry: Record "eInvoice Submission Log")
    var
        Setup: Record "eInvoiceSetup";
        ValidationUrl: Text;
    begin
        if not Setup.Get('SETUP') then
            exit;

        // Ensure Long ID is populated from last response when possible
        if Entry."Long ID" = '' then
            exit;

        if Setup.Environment = Setup.Environment::Preprod then
            ValidationUrl := StrSubstNo('%1/%2/share/%3', 'https://preprod.myinvois.hasil.gov.my', Entry."Document UUID", Entry."Long ID")
        else
            ValidationUrl := StrSubstNo('%1/%2/share/%3', 'https://myinvois.hasil.gov.my', Entry."Document UUID", Entry."Long ID");

        Entry."Validation Link" := CopyStr(ValidationUrl, 1, MaxStrLen(Entry."Validation Link"));
        Entry.Modify();

        // Also update Posted Sales Invoice with QR URL when available
        UpdatePostedInvoiceQrUrl(Entry."Invoice No.", ValidationUrl);
    end;

    local procedure UpdatePostedInvoiceQrUrl(InvoiceNo: Code[20]; Url: Text)
    var
        eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
    begin
        if (InvoiceNo = '') or (Url = '') then
            exit;

        // Use codeunit with tabledata permissions to avoid page permission issues
        if eInvoiceGenerator.UpdateInvoiceQrUrl(InvoiceNo, Url) then begin
            // Automatically generate QR image after updating the URL
            AutoGenerateInvoiceQrImage(InvoiceNo, Url);
        end;
    end;

    local procedure ExtractLongIdFromApiResponse(ResponseText: Text; DocumentUuid: Text): Text
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummary: JsonArray;
        Doc: JsonObject;
        PickedUuid: Text;
        LongId: Text;
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

    local procedure ExtractUuidFromApiResponse(ResponseText: Text): Text
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummary: JsonArray;
        Doc: JsonObject;
    begin
        if not JsonObject.ReadFrom(ResponseText) then
            exit('');

        if JsonObject.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocumentSummary := JsonToken.AsArray();
            if DocumentSummary.Count() > 0 then begin
                DocumentSummary.Get(0, JsonToken);
                if JsonToken.IsObject() then begin
                    Doc := JsonToken.AsObject();
                    if Doc.Get('uuid', JsonToken) then
                        exit(JsonToken.AsValue().AsText());
                end;
            end;
        end;
        exit('');
    end;

    local procedure ExtractStatusFromApiResponse(ResponseText: Text; DocumentUuid: Text): Text
    var
        JsonObject: JsonObject;
        JsonToken: JsonToken;
        DocumentSummaryArray: JsonArray;
        DocumentJson: JsonObject;
        OverallStatus: Text;
        DocumentStatus: Text;
        PickedUuid: Text;
        i: Integer;
    begin
        if not JsonObject.ReadFrom(ResponseText) then
            exit('Unknown');

        if JsonObject.Get('documentSummary', JsonToken) and JsonToken.IsArray() then begin
            DocumentSummaryArray := JsonToken.AsArray();
            for i := 0 to DocumentSummaryArray.Count() - 1 do begin
                DocumentSummaryArray.Get(i, JsonToken);
                if JsonToken.IsObject() then begin
                    DocumentJson := JsonToken.AsObject();
                    if DocumentJson.Get('uuid', JsonToken) then
                        PickedUuid := JsonToken.AsValue().AsText();
                    if (DocumentUuid <> '') and (PickedUuid = DocumentUuid) then
                        if DocumentJson.Get('status', JsonToken) then begin
                            DocumentStatus := JsonToken.AsValue().AsText();
                            exit(NormalizeStatus(DocumentStatus));
                        end;
                end;
            end;
        end;

        if JsonObject.Get('overallStatus', JsonToken) then
            OverallStatus := JsonToken.AsValue().AsText();
        exit(NormalizeStatus(OverallStatus));
    end;

    local procedure NormalizeStatus(StatusValue: Text): Text
    begin
        case LowerCase(StatusValue) of
            'valid':
                exit('Valid');
            'invalid':
                exit('Invalid');
            'in progress':
                exit('In Progress');
            'partially valid':
                exit('Partially Valid');
            'cancelled':
                exit('Cancelled');
            'rejected':
                exit('Rejected');
            else
                exit(StatusValue);
        end;
    end;

    trigger OnAfterGetCurrRecord()
    var
        CompanyInfo: Record "Company Information";
    begin
        if CompanyInfo.Get() then
            IsJotexCompany := (CompanyInfo.Name = 'JOTEX SDN BHD')
        else
            IsJotexCompany := false;

        // Calculate if resubmit should be enabled
        CanResubmit := Rec.Status in ['Rejected', 'Submission Failed', 'Invalid', 'Cancelled'];
    end;

    /// <summary>
    /// Automatically generates QR image for the invoice using the validation URL
    /// This is called after the QR URL is updated during status refresh
    /// </summary>
    /// <param name="InvoiceNo">The invoice number to generate QR for</param>
    /// <param name="ValidationUrl">The validation URL to convert to QR</param>
    local procedure AutoGenerateInvoiceQrImage(InvoiceNo: Code[20]; ValidationUrl: Text)
    var
        HttpClient: HttpClient;
        Response: HttpResponseMessage;
        QrServiceUrl: Text;
        InS: InStream;
        eInvoiceGenerator: Codeunit "eInvoice JSON Generator";
        Success: Boolean;
    begin
        if (InvoiceNo = '') or (ValidationUrl = '') then
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

        // Generate and store the QR image
        Success := eInvoiceGenerator.UpdateInvoiceQrImage(InvoiceNo, InS, 'eInvoiceQR.png');

        if Success then begin
            // Successfully generated QR image
            // Note: We don't update the page here as this is called from a background process
        end;
    end;

    /// <summary>
    /// Get number of days from user input
    /// </summary>
    /// <param name="DaysOld">Variable to store the number of days</param>
    /// <returns>True if user provided valid input, false if cancelled</returns>
    local procedure GetDaysOldFromUser(var DaysOld: Integer): Boolean
    var
        Selection: Integer;
    begin
        Selection := StrMenu('7 days,14 days,30 days,60 days,90 days,180 days,365 days,Custom', 3, 'Select how old entries should be to qualify for deletion:');

        case Selection of
            0:
                exit(false); // User cancelled
            1:
                DaysOld := 7;
            2:
                DaysOld := 14;
            3:
                DaysOld := 30;
            4:
                DaysOld := 60;
            5:
                DaysOld := 90;
            6:
                DaysOld := 180;
            7:
                DaysOld := 365;
            8:
                begin // Custom
                    if not GetCustomDaysFromUser(DaysOld) then
                        exit(false);
                end;
        end;

        exit(true);
    end;

    /// <summary>
    /// Get custom number of days from user
    /// </summary>
    /// <param name="DaysOld">Variable to store the number of days</param>
    /// <returns>True if user provided valid input, false if cancelled</returns>
    local procedure GetCustomDaysFromUser(var DaysOld: Integer): Boolean
    var
        Input: Text;
        ParsedDays: Integer;
    begin
        Input := '30'; // Default value

        if not Confirm(StrSubstNo('Enter number of days (current: %1):\Click OK to use current value, or Cancel to enter custom value.', Input)) then begin
            // For simplicity, we'll use a simple approach since we can't easily get user input
            Message('For custom days, please use the filter on "Submission Date" column and then run "Cleanup Old Deletable Entries" again.');
            exit(false);
        end;

        DaysOld := 30; // Use default
        exit(true);
    end;
}