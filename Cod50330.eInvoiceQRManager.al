codeunit 50330 "eInvoice QR Manager"
{
    Permissions = tabledata "Sales Cr.Memo Header" = M;

    procedure UpdateCreditMemoQrUrl(CreditMemoNo: Code[20]; Url: Text): Boolean
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        if (CreditMemoNo = '') or (Url = '') then
            exit(false);

        if not SalesCrMemoHeader.Get(CreditMemoNo) then
            exit(false);

        SalesCrMemoHeader."eInv QR URL" := CopyStr(Url, 1, MaxStrLen(SalesCrMemoHeader."eInv QR URL"));
        SalesCrMemoHeader.Modify();
        exit(true);
    end;

    procedure UpdateCreditMemoQrImage(CreditMemoNo: Code[20]; var InS: InStream; FileName: Text): Boolean
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        if CreditMemoNo = '' then
            exit(false);

        if not SalesCrMemoHeader.Get(CreditMemoNo) then
            exit(false);

        SalesCrMemoHeader."eInv QR Image".ImportStream(InS, FileName);
        SalesCrMemoHeader.Modify();
        exit(true);
    end;
}


