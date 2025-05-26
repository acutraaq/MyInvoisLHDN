pageextension 50302 MyInvPostedSalesPDFExt extends "Posted Sales Invoice"
{
    actions
    {
        addlast(Processing)
        {
            action(ViewMyInvoisPDF)
            {
                Caption = 'View PDF (MyInvois)';
                ApplicationArea = All;
                Image = Document;

                trigger OnAction()
                begin
                    if Rec."MyInvois PDF URL" = '' then
                        Error('No MyInvois PDF URL available for this invoice.');

                    HYPERLINK(Rec."MyInvois PDF URL");
                end;
            }
        }
    }
}
