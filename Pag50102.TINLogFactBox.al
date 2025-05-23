page 50102 "TIN Log FactBox"
{
    PageType = ListPart;
    SourceTable = "MyInvois TIN Log";
    ApplicationArea = All;
    Caption = 'TIN Validation History';
    Editable = false;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field("Response Time"; Rec."Response Time") { }
                field("TIN"; Rec.TIN) { }
                field("TIN Status"; Rec."TIN Status") { }
                field("TIN Name (API)"; Rec."TIN Name (API)") { }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        // Optional formatting or logic
    end;
}
