page 50303 "MyInvois QR FactBox"
{
    PageType = CardPart;
    SourceTable = "Sales Invoice Header";
    ApplicationArea = All;
    Caption = 'MyInvois QR Code';
    Editable = false;

    layout
    {
        area(content)
        {
            group(QR)
            {
                field("MyInvois QR Image"; Rec."MyInvois QR Image")
                {
                    ApplicationArea = All;
                    ShowCaption = false;
                }
            }
        }
    }
}
