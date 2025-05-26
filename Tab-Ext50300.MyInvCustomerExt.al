tableextension 50300 MyInvCustomerExt extends Customer
{
    fields
    {
        field(50100; "Last Validated TIN Name"; Text[100]) { Caption = 'TIN Registered Name'; }
        field(50101; "Last TIN Validation"; DateTime) { Caption = 'Last TIN Validation'; }
    }
}
