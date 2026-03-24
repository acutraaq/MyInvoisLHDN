page 50327 "eInvoice QR CM FactBox"
{
    PageType = CardPart;
    SourceTable = "Sales Cr.Memo Header";
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
                ToolTip = 'Displays the e-Invoice QR image when available.';
                Editable = false;
            }
        }
    }

    // No CALCFIELDS needed for Media field; remove to avoid FlowField error
}


