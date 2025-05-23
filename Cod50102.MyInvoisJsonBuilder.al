codeunit 50102 "MyInvois Json Builder"
{
    procedure BuildInvoiceJson(SalesInvHeader: Record "Sales Invoice Header"): JsonObject
    var
        JsonRoot, JsonSeller, JsonBuyer, JsonSummary, JsonItem : JsonObject;
        JsonItems: JsonArray;
        SalesInvLine: Record "Sales Invoice Line";
        CompanyInfo: Record "Company Information";
        LineVATAmount: Decimal;
        FullAddress: Text;
    begin
        // ✅ Base info
        JsonRoot.Add('invoiceType', '01');
        JsonRoot.Add('invoiceDate', Format(SalesInvHeader."Posting Date", 0, '<Year4>-<Month2>-<Day2>T00:00:00+08:00'));
        JsonRoot.Add('currency', 'MYR');

        // ✅ Seller info
        if not CompanyInfo.Get() then
            Error('Company Information is not set.');

        FullAddress := CompanyInfo.Address + ', ' + CompanyInfo.City;
        JsonSeller.Add('taxRegID', CompanyInfo."VAT Registration No.");
        JsonSeller.Add('name', CompanyInfo.Name);
        JsonSeller.Add('address', FullAddress);
        JsonRoot.Add('seller', JsonSeller);

        // ✅ Buyer info
        JsonBuyer.Add('taxRegID', SalesInvHeader."VAT Registration No.");
        JsonBuyer.Add('name', SalesInvHeader."Sell-to Customer Name");
        JsonBuyer.Add('address', SalesInvHeader."Sell-to Address");
        JsonRoot.Add('buyer', JsonBuyer);

        // ✅ Item list
        SalesInvLine.SetRange("Document No.", SalesInvHeader."No.");
        if SalesInvLine.FindSet() then
            repeat
                if SalesInvLine.Quantity = 0 then
                    continue;

                Clear(JsonItem);
                LineVATAmount := Round(SalesInvLine."Amount Including VAT" - SalesInvLine."Line Amount", 0.01);

                JsonItem.Add('description', SalesInvLine.Description);
                JsonItem.Add('quantity', SalesInvLine.Quantity);
                JsonItem.Add('unitPrice', SalesInvLine."Unit Price");
                JsonItem.Add('taxAmount', LineVATAmount);
                JsonItem.Add('totalAmount', SalesInvLine."Amount Including VAT");
                JsonItem.Add('taxCode', '01');
                JsonItems.Add(JsonItem);
            until SalesInvLine.Next() = 0;
        JsonRoot.Add('itemList', JsonItems);

        // ✅ Summary
        JsonSummary.Add('totalExclTax', SalesInvHeader.Amount);
        JsonSummary.Add('totalTax', Round(SalesInvHeader."Amount Including VAT" - SalesInvHeader.Amount, 0.01));
        JsonSummary.Add('totalInclTax', SalesInvHeader."Amount Including VAT");
        JsonRoot.Add('summary', JsonSummary);

        exit(JsonRoot);
    end;
}
