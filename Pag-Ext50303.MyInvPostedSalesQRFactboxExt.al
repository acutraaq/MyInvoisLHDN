pageextension 50303 MyInvPostedSalesQRFactboxExt extends "Posted Sales Invoice"
{
    layout
    {
        addlast(FactBoxes)
        {
            part(MyInvoisQRFactBox; "MyInvois QR FactBox")
            {
                ApplicationArea = All;
                SubPageLink = "No." = FIELD("No.");
            }
        }
    }
}
