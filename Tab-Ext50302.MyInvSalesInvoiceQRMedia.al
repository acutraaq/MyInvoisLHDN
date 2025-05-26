tableextension 50302 MyInvSalesInvoiceQRMedia extends "Sales Invoice Header"
{
    fields
    {
        field(50103; "MyInvois QR Image"; Media)
        {
            Caption = 'MyInvois QR Image';
            DataClassification = CustomerContent;
        }
    }
}
