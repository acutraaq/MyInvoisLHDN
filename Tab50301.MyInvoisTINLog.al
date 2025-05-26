table 50301 "MyInvois TIN Log"
{
    Caption = 'MyInvois TIN Log';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            DataClassification = SystemMetadata;
            AutoIncrement = true;
        }

        field(2; "Customer No."; Code[20]) { }
        field(3; "Customer Name"; Text[100]) { }
        field(4; "TIN"; Code[20]) { }
        field(5; "TIN Status"; Text[30]) { }
        field(6; "TIN Name (API)"; Text[100]) { }
        field(7; "Response Time"; DateTime) { }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
    }
}
