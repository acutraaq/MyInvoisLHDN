page 50301 "TIN Validation Log"
{
    PageType = List;
    SourceTable = "MyInvois TIN Log";
    ApplicationArea = All;
    UsageCategory = Lists;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field("Entry No."; Rec."Entry No.") { }
                field("Customer No."; Rec."Customer No.") { }
                field("Customer Name"; Rec."Customer Name") { }
                field("TIN"; Rec.TIN) { }
                field("TIN Status"; Rec."TIN Status") { }
                field("TIN Name (API)"; Rec."TIN Name (API)") { }
                field("Response Time"; Rec."Response Time") { }
            }
        }
    }
}
