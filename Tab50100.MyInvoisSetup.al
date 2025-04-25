table 50100 MyInvoisSetup
{
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10]) { DataClassification = SystemMetadata; }
        field(2; "Client ID"; Text[100]) { DataClassification = SystemMetadata; }
        field(3; "Client Secret"; Text[100]) { DataClassification = SystemMetadata; }
        field(4; "Environment"; Option)
        {
            OptionMembers = Preprod,Production;
            DataClassification = SystemMetadata;
        }
        field(5; "Last Token"; Text[500]) { DataClassification = SystemMetadata; Editable = false; }
        field(6; "Token Timestamp"; DateTime) { DataClassification = SystemMetadata; Editable = false; }
    }

    keys
    {
        key(PK; "Primary Key") { Clustered = true; }
    }
}
