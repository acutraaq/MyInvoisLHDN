tableextension 50301 MyInvSalesInvoiceExt extends "Sales Invoice Header"
{
    fields
    {
        field(50100; "MyInvois UUID"; Text[100])
        {
            Caption = 'MyInvois UUID';
        }
        field(50101; "MyInvois QR URL"; Text[250])
        {
            Caption = 'QR URL';
        }
        field(50102; "MyInvois PDF URL"; Text[250])
        {
            Caption = 'PDF URL';
        }
        field(50104; "MyInvois Submission UID"; Text[100])
        {
            Caption = 'Submission UID';
        }
    }
}
