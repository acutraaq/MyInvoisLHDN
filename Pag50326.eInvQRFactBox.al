page 50326 "eInvoice QR FactBox"
{
    PageType = CardPart;
    SourceTable = "Sales Invoice Header";
    ApplicationArea = All;
    Caption = 'e-Invoice QR';

    layout
    {
        area(content)
        {
            field("eInv QR Image"; Rec."eInv QR Image")
            {
                ApplicationArea = All;
                ShowCaption = false;
                ToolTip = 'Displays the e-Invoice QR as an image when available.';
            }
        }
    }
}


