codeunit 50311 "eInvoice UBL Document Builder"
{
    // Enhanced UBL Document Builder inspired by myinvois-client patterns
    // Provides structured approach to UBL document construction
    // Includes validation and helper methods for common UBL elements

    procedure BuildInvoiceDocument(SalesInvoiceHeader: Record "Sales Invoice Header") UBLDocument: JsonObject
    var
        DocumentBuilder: JsonObject;
        InvoiceTypeCode: Text;
        CurrencyCode: Text;
        DocumentCurrencyCode: Text;
    begin
        // Initialize document structure following UBL 2.1 standard
        InitializeUBLStructure(UBLDocument);

        // Build core invoice identification
        BuildInvoiceIdentification(UBLDocument, SalesInvoiceHeader);

        // Build parties (supplier and customer)
        BuildSupplierParty(UBLDocument, SalesInvoiceHeader);
        BuildCustomerParty(UBLDocument, SalesInvoiceHeader);

        // TODO: Implement additional document components
        // BuildDocumentReferences(UBLDocument, SalesInvoiceHeader);
        // BuildDeliveryInformation(UBLDocument, SalesInvoiceHeader);

        // TODO: Implement payment information
        // BuildPaymentMeans(UBLDocument, SalesInvoiceHeader);
        // BuildPaymentTerms(UBLDocument, SalesInvoiceHeader);

        // TODO: Implement tax information
        // BuildTaxTotal(UBLDocument, SalesInvoiceHeader);

        // TODO: Implement monetary totals
        // BuildLegalMonetaryTotal(UBLDocument, SalesInvoiceHeader);

        // Build invoice lines
        BuildInvoiceLines(UBLDocument, SalesInvoiceHeader);

        // Validate final document structure
        if not ValidateUBLDocument(UBLDocument) then
            Error('UBL Document validation failed\\\\Please check document structure and required fields.');
    end;

    local procedure InitializeUBLStructure(var UBLDocument: JsonObject)
    var
        NamespaceObject: JsonObject;
    begin
        // Set UBL namespace and schema information (following myinvois standards)
        UBLDocument.Add('_declaration', CreateXMLDeclaration());
        UBLDocument.Add('Invoice', CreateInvoiceRoot());
    end;

    local procedure CreateXMLDeclaration() Declaration: JsonObject
    begin
        Declaration.Add('_attributes', CreateXMLAttributes());
    end;

    local procedure CreateXMLAttributes() Attributes: JsonObject
    begin
        Attributes.Add('version', '1.0');
        Attributes.Add('encoding', 'UTF-8');
    end;

    local procedure CreateInvoiceRoot() InvoiceRoot: JsonObject
    var
        AttributesObject: JsonObject;
    begin
        // UBL Invoice root element with required namespaces
        AttributesObject.Add('xmlns', 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2');
        AttributesObject.Add('xmlns:cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2');
        AttributesObject.Add('xmlns:cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2');

        InvoiceRoot.Add('_attributes', AttributesObject);
    end;

    local procedure BuildInvoiceIdentification(var UBLDocument: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        UBLVersionID: JsonObject;
        CustomizationID: JsonObject;
        ProfileID: JsonObject;
        ID: JsonObject;
        IssueDate: JsonObject;
        IssueTime: JsonObject;
        InvoiceTypeCode: JsonObject;
        DocumentCurrencyCode: JsonObject;
    begin
        // Get invoice object from UBL structure
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // UBL Version (required by myinvois)
        UBLVersionID.Add('_text', '2.1');
        InvoiceObject.Add('cbc:UBLVersionID', UBLVersionID);

        // Customization ID (Malaysia e-Invoice specific)
        CustomizationID.Add('_text', 'MY:1.0');
        InvoiceObject.Add('cbc:CustomizationID', CustomizationID);

        // Profile ID (Malaysia e-Invoice profile)
        ProfileID.Add('_text', 'reporting:1.0');
        InvoiceObject.Add('cbc:ProfileID', ProfileID);

        // Invoice Number
        ID.Add('_text', SalesInvoiceHeader."No.");
        InvoiceObject.Add('cbc:ID', ID);

        // FORCE: Always use yesterday's date to ensure it's never in the future
        IssueDate.Add('_text', Format(CalcDate('-1D', Today()), 0, '<Year4>-<Month,2>-<Day,2>'));
        InvoiceObject.Add('cbc:IssueDate', IssueDate);

        IssueTime.Add('_text', Format(DT2Time(CurrentDateTime - 300000), 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        InvoiceObject.Add('cbc:IssueTime', IssueTime);

        // Invoice Type Code (01 = Invoice, 02 = Debit Note, 03 = Credit Note)
        InvoiceTypeCode.Add('_text', GetInvoiceTypeCode(SalesInvoiceHeader));
        InvoiceObject.Add('cbc:InvoiceTypeCode', InvoiceTypeCode);

        // Document Currency Code
        DocumentCurrencyCode.Add('_text', GetDocumentCurrencyCode(SalesInvoiceHeader));
        InvoiceObject.Add('cbc:DocumentCurrencyCode', DocumentCurrencyCode);

        // Update the document
        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    local procedure BuildSupplierParty(var UBLDocument: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        AccountingSupplierParty: JsonObject;
        PartyObject: JsonObject;
        PartyIdentification: JsonObject;
        PartyName: JsonObject;
        PostalAddress: JsonObject;
        PartyTaxScheme: JsonObject;
        PartyLegalEntity: JsonObject;
        Contact: JsonObject;
        CompanyInfo: Record "Company Information";
    begin
        CompanyInfo.Get();
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Build supplier party structure with basic information
        BuildPartyIdentification(PartyIdentification, CompanyInfo."Registration No.");
        PartyObject.Add('cac:PartyIdentification', PartyIdentification);

        BuildPartyName(PartyName, CompanyInfo.Name);
        PartyObject.Add('cac:PartyName', PartyName);

        // TODO: Implement additional party components
        // BuildSupplierPostalAddress(PostalAddress, CompanyInfo);
        // PartyObject.Add('cac:PostalAddress', PostalAddress);

        // BuildPartyTaxScheme(PartyTaxScheme, CompanyInfo."VAT Registration No.");
        // PartyObject.Add('cac:PartyTaxScheme', PartyTaxScheme);

        // BuildPartyLegalEntity(PartyLegalEntity, CompanyInfo.Name, CompanyInfo."Registration No.");
        // PartyObject.Add('cac:PartyLegalEntity', PartyLegalEntity);

        // BuildSupplierContact(Contact, CompanyInfo);
        // PartyObject.Add('cac:Contact', Contact);

        AccountingSupplierParty.Add('cac:Party', PartyObject);
        InvoiceObject.Add('cac:AccountingSupplierParty', AccountingSupplierParty);

        UBLDocument.Replace('Invoice', InvoiceToken);
    end;

    local procedure BuildCustomerParty(var UBLDocument: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        AccountingCustomerParty: JsonObject;
        PartyObject: JsonObject;
        PartyIdentification: JsonObject;
        PartyName: JsonObject;
        PostalAddress: JsonObject;
        PartyTaxScheme: JsonObject;
        PartyLegalEntity: JsonObject;
        Contact: JsonObject;
        Customer: Record Customer;
        CustomerTIN: Text;
    begin
        Customer.Get(SalesInvoiceHeader."Sell-to Customer No.");
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Use VAT Registration No. as TIN placeholder
        CustomerTIN := Customer."VAT Registration No.";
        if CustomerTIN = '' then
            CustomerTIN := Customer."No."; // Fallback to customer number

        // Build customer party structure with basic information
        BuildPartyIdentification(PartyIdentification, CustomerTIN);
        PartyObject.Add('cac:PartyIdentification', PartyIdentification);

        BuildPartyName(PartyName, SalesInvoiceHeader."Sell-to Customer Name");
        PartyObject.Add('cac:PartyName', PartyName);

        // TODO: Implement additional party components
        // BuildCustomerPostalAddress(PostalAddress, SalesInvoiceHeader);
        // PartyObject.Add('cac:PostalAddress', PostalAddress);

        // BuildPartyTaxScheme(PartyTaxScheme, Customer."VAT Registration No.");
        // PartyObject.Add('cac:PartyTaxScheme', PartyTaxScheme);

        // BuildPartyLegalEntity(PartyLegalEntity, SalesInvoiceHeader."Sell-to Customer Name", CustomerTIN);
        // PartyObject.Add('cac:PartyLegalEntity', PartyLegalEntity);

        // BuildCustomerContact(Contact, Customer, SalesInvoiceHeader);
        // PartyObject.Add('cac:Contact', Contact);

        AccountingCustomerParty.Add('cac:Party', PartyObject);
        InvoiceObject.Add('cac:AccountingCustomerParty', AccountingCustomerParty);

        UBLDocument.Replace('Invoice', InvoiceToken);
    end;

    // Overloaded version for credit memos
    local procedure BuildSupplierParty(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        AccountingSupplierParty: JsonObject;
        PartyObject: JsonObject;
        PartyIdentification: JsonObject;
        PartyName: JsonObject;
        PostalAddress: JsonObject;
        PartyTaxScheme: JsonObject;
        PartyLegalEntity: JsonObject;
        Contact: JsonObject;
        CompanyInfo: Record "Company Information";
    begin
        CompanyInfo.Get();
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Build supplier party structure with basic information
        BuildPartyIdentification(PartyIdentification, CompanyInfo."Registration No.");
        PartyObject.Add('cac:PartyIdentification', PartyIdentification);

        BuildPartyName(PartyName, CompanyInfo.Name);
        PartyObject.Add('cac:PartyName', PartyName);

        // TODO: Implement additional party components
        // BuildSupplierPostalAddress(PostalAddress, CompanyInfo);
        // PartyObject.Add('cac:PostalAddress', PostalAddress);

        // BuildPartyTaxScheme(PartyTaxScheme, CompanyInfo."VAT Registration No.");
        // PartyObject.Add('cac:PartyTaxScheme', PartyTaxScheme);

        // BuildPartyLegalEntity(PartyLegalEntity, CompanyInfo.Name, CompanyInfo."Registration No.");
        // PartyObject.Add('cac:PartyLegalEntity', PartyLegalEntity);

        // BuildSupplierContact(Contact, CompanyInfo);
        // PartyObject.Add('cac:Contact', Contact);

        AccountingSupplierParty.Add('cac:Party', PartyObject);
        CreditNoteObject.Add('cac:AccountingSupplierParty', AccountingSupplierParty);

        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // Overloaded version for credit memos
    local procedure BuildCustomerParty(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        AccountingCustomerParty: JsonObject;
        PartyObject: JsonObject;
        PartyIdentification: JsonObject;
        PartyName: JsonObject;
        PostalAddress: JsonObject;
        PartyTaxScheme: JsonObject;
        PartyLegalEntity: JsonObject;
        Contact: JsonObject;
        Customer: Record Customer;
        CustomerTIN: Text;
    begin
        Customer.Get(SalesCrMemoHeader."Sell-to Customer No.");
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Use VAT Registration No. as TIN placeholder
        CustomerTIN := Customer."VAT Registration No.";
        if CustomerTIN = '' then
            CustomerTIN := Customer."No."; // Fallback to customer number

        // Build customer party structure with basic information
        BuildPartyIdentification(PartyIdentification, CustomerTIN);
        PartyObject.Add('cac:PartyIdentification', PartyIdentification);

        BuildPartyName(PartyName, SalesCrMemoHeader."Sell-to Customer Name");
        PartyObject.Add('cac:PartyName', PartyName);

        // TODO: Implement additional party components
        // BuildCustomerPostalAddress(PostalAddress, SalesCrMemoHeader);
        // PartyObject.Add('cac:PostalAddress', PostalAddress);

        // BuildPartyTaxScheme(PartyTaxScheme, Customer."VAT Registration No.");
        // PartyObject.Add('cac:PartyTaxScheme', PartyTaxScheme);

        // BuildPartyLegalEntity(PartyLegalEntity, SalesCrMemoHeader."Sell-to Customer Name", CustomerTIN);
        // PartyObject.Add('cac:PartyLegalEntity', PartyLegalEntity);

        // BuildCustomerContact(Contact, Customer, SalesCrMemoHeader);
        // PartyObject.Add('cac:Contact', Contact);

        AccountingCustomerParty.Add('cac:Party', PartyObject);
        CreditNoteObject.Add('cac:AccountingCustomerParty', AccountingCustomerParty);

        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    local procedure BuildInvoiceLines(var UBLDocument: JsonObject; SalesInvoiceHeader: Record "Sales Invoice Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        InvoiceLinesArray: JsonArray;
        SalesInvoiceLine: Record "Sales Invoice Line";
    begin
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        SalesInvoiceLine.SetRange("Document No.", SalesInvoiceHeader."No.");
        SalesInvoiceLine.SetFilter(Type, '<>%1', SalesInvoiceLine.Type::" ");
        SalesInvoiceLine.SetFilter(Quantity, '<>0');

        if SalesInvoiceLine.FindSet() then
            repeat
                BuildSingleInvoiceLine(InvoiceLinesArray, SalesInvoiceLine);
            until SalesInvoiceLine.Next() = 0;

        InvoiceObject.Add('cac:InvoiceLine', InvoiceLinesArray);
        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    local procedure BuildSingleInvoiceLine(var InvoiceLinesArray: JsonArray; SalesInvoiceLine: Record "Sales Invoice Line")
    var
        InvoiceLineObject: JsonObject;
        ID: JsonObject;
        InvoicedQuantity: JsonObject;
        LineExtensionAmount: JsonObject;
        TaxTotal: JsonObject;
        Item: JsonObject;
        Price: JsonObject;
        ClassifiedTaxCategory: JsonObject;
    begin
        // Line ID
        ID.Add('_text', Format(SalesInvoiceLine."Line No."));
        InvoiceLineObject.Add('cbc:ID', ID);

        // TODO: Implement line detail builders
        // BuildInvoicedQuantity(InvoicedQuantity, SalesInvoiceLine);
        // InvoiceLineObject.Add('cbc:InvoicedQuantity', InvoicedQuantity);

        // BuildLineExtensionAmount(LineExtensionAmount, SalesInvoiceLine);
        // InvoiceLineObject.Add('cbc:LineExtensionAmount', LineExtensionAmount);

        // BuildLineTaxTotal(TaxTotal, SalesInvoiceLine);
        // InvoiceLineObject.Add('cac:TaxTotal', TaxTotal);

        // BuildItemInformation(Item, SalesInvoiceLine);
        // InvoiceLineObject.Add('cac:Item', Item);

        // BuildPriceInformation(Price, SalesInvoiceLine);
        // InvoiceLineObject.Add('cac:Price', Price);

        InvoiceLinesArray.Add(InvoiceLineObject);
    end;

    // Helper methods for building specific UBL components
    local procedure BuildPartyIdentification(var PartyIdentification: JsonObject; IdentificationNumber: Text)
    var
        ID: JsonObject;
        IdentificationArray: JsonArray;
        IdentificationObject: JsonObject;
    begin
        ID.Add('_text', IdentificationNumber);
        ID.Add('_attributes', CreateSchemeAttributes('TIN'));
        IdentificationObject.Add('cbc:ID', ID);
        IdentificationArray.Add(IdentificationObject);
        PartyIdentification := IdentificationObject;
    end;

    local procedure BuildPartyName(var PartyName: JsonObject; Name: Text)
    var
        NameElement: JsonObject;
        NameArray: JsonArray;
    begin
        NameElement.Add('_text', Name);
        PartyName.Add('cbc:Name', NameElement);
    end;

    local procedure CreateSchemeAttributes(SchemeID: Text) Attributes: JsonObject
    begin
        Attributes.Add('schemeID', SchemeID);
    end;

    local procedure GetInvoiceTypeCode(SalesInvoiceHeader: Record "Sales Invoice Header") TypeCode: Text
    begin
        // Standard invoice type codes for myinvois
        TypeCode := '01'; // Standard Invoice

        // Could be extended based on document type or custom fields
        // 02 = Debit Note, 03 = Credit Note, etc.
    end;

    local procedure GetDocumentCurrencyCode(SalesInvoiceHeader: Record "Sales Invoice Header") CurrencyCode: Text
    begin
        if SalesInvoiceHeader."Currency Code" <> '' then
            CurrencyCode := SalesInvoiceHeader."Currency Code"
        else
            CurrencyCode := 'MYR'; // Default Malaysian Ringgit
    end;

    local procedure ValidateUBLDocument(UBLDocument: JsonObject) IsValid: Boolean
    var
        DocumentObject: JsonToken;
        RequiredElements: List of [Text];
        ElementName: Text;
        RootElementName: Text;
    begin
        // Dynamic validation for both Invoice and CreditNote documents
        if UBLDocument.Get('Invoice', DocumentObject) then
            RootElementName := 'Invoice'
        else if UBLDocument.Get('CreditNote', DocumentObject) then
            RootElementName := 'CreditNote'
        else
            exit(false);

        // Check for required elements (common to both Invoice and CreditNote)
        RequiredElements.Add('cbc:ID');
        RequiredElements.Add('cbc:IssueDate');
        RequiredElements.Add('cbc:InvoiceTypeCode');
        RequiredElements.Add('cbc:DocumentCurrencyCode');
        RequiredElements.Add('cac:AccountingSupplierParty');
        RequiredElements.Add('cac:AccountingCustomerParty');

        foreach ElementName in RequiredElements do
            if not DocumentObject.AsObject().Contains(ElementName) then
                exit(false);

        IsValid := true;
    end;



    /// <summary>
    /// Builds credit memo document in the correct UBL format for LHDN
    /// This generates the proper structure that matches the sample format
    /// </summary>
    procedure BuildCreditMemoDocumentCorrectFormat(SalesCrMemoHeader: Record "Sales Cr.Memo Header") UBLDocument: JsonObject
    var
        InvoiceArray: JsonArray;
        InvoiceObject: JsonObject;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        LineArray: JsonArray;
        LineObject: JsonObject;
        CompanyInfo: Record "Company Information";
        Customer: Record Customer;
        TotalAmount: Decimal;
        TotalTaxAmount: Decimal;
        LineAmount: Decimal;
        LineTaxAmount: Decimal;
    begin
        CompanyInfo.Get();
        Customer.Get(SalesCrMemoHeader."Sell-to Customer No.");

        // Calculate totals
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        if SalesCrMemoLine.FindSet() then
            repeat
                LineAmount := SalesCrMemoLine."Line Amount";
                LineTaxAmount := SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine."Line Amount";
                TotalAmount += LineAmount;
                TotalTaxAmount += LineTaxAmount;
            until SalesCrMemoLine.Next() = 0;

        // Build the main invoice object (Credit Note uses Invoice structure)
        BuildCreditNoteMainStructure(InvoiceObject, SalesCrMemoHeader, CompanyInfo, Customer, TotalAmount, TotalTaxAmount);

        // Build invoice lines
        BuildCreditMemoLines(InvoiceObject, SalesCrMemoHeader);

        // Add to array (LHDN expects array format)
        InvoiceArray.Add(InvoiceObject);
        UBLDocument.Add('Invoice', InvoiceArray);
    end;

    /// <summary>
    /// Builds the main credit note structure following the sample format
    /// </summary>
    local procedure BuildCreditNoteMainStructure(var InvoiceObject: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header"; CompanyInfo: Record "Company Information"; Customer: Record Customer; TotalAmount: Decimal; TotalTaxAmount: Decimal)
    var
        IDArray: JsonArray;
        IDObject: JsonObject;
        IssueDateArray: JsonArray;
        IssueDateObject: JsonObject;
        IssueTimeArray: JsonArray;
        IssueTimeObject: JsonObject;
        InvoiceTypeCodeArray: JsonArray;
        InvoiceTypeCodeObject: JsonObject;
        DocumentCurrencyCodeArray: JsonArray;
        DocumentCurrencyCodeObject: JsonObject;
        TaxCurrencyCodeArray: JsonArray;
        TaxCurrencyCodeObject: JsonObject;
        InvoicePeriodArray: JsonArray;
        InvoicePeriodObject: JsonObject;
        StartDateArray: JsonArray;
        StartDateObject: JsonObject;
        EndDateArray: JsonArray;
        EndDateObject: JsonObject;
        DescriptionArray: JsonArray;
        DescriptionObject: JsonObject;
        BillingReferenceArray: JsonArray;
        BillingReferenceObject: JsonObject;
        InvoiceDocumentReferenceArray: JsonArray;
        InvoiceDocumentReferenceObject: JsonObject;
        ID2Object: JsonObject;
        UUIDObject: JsonObject;
        AdditionalDocumentReferenceArray: JsonArray;
        AdditionalDocumentReferenceObject: JsonObject;
        ID3Object: JsonObject;
        DocumentTypeObject: JsonObject;
        AccountingSupplierPartyArray: JsonArray;
        AccountingSupplierPartyObject: JsonObject;
        PartyObject: JsonObject;
        IndustryClassificationCodeArray: JsonArray;
        IndustryClassificationCodeObject: JsonObject;
        PartyIdentificationArray: JsonArray;
        PartyIdentificationObject: JsonObject;
        ID4Object: JsonObject;
        SchemeIDObject: JsonObject;
        BRNObject: JsonObject;
        ID5Object: JsonObject;
        SchemeID2Object: JsonObject;
        SSTObject: JsonObject;
        ID6Object: JsonObject;
        SchemeID3Object: JsonObject;
        TTXObject: JsonObject;
        ID7Object: JsonObject;
        SchemeID4Object: JsonObject;
        PostalAddressArray: JsonArray;
        PostalAddressObject: JsonObject;
        CityNameArray: JsonArray;
        CityNameObject: JsonObject;
        PostalZoneArray: JsonArray;
        PostalZoneObject: JsonObject;
        CountrySubentityCodeArray: JsonArray;
        CountrySubentityCodeObject: JsonObject;
        AddressLineArray: JsonArray;
        AddressLineObject: JsonObject;
        LineArray: JsonArray;
        LineObject: JsonObject;
        CountryArray: JsonArray;
        CountryObject: JsonObject;
        IdentificationCodeArray: JsonArray;
        IdentificationCodeObject: JsonObject;
        PartyLegalEntityArray: JsonArray;
        PartyLegalEntityObject: JsonObject;
        RegistrationNameArray: JsonArray;
        RegistrationNameObject: JsonObject;
        ContactArray: JsonArray;
        ContactObject: JsonObject;
        TelephoneArray: JsonArray;
        TelephoneObject: JsonObject;
        ElectronicMailArray: JsonArray;
        ElectronicMailObject: JsonObject;
        AdditionalAccountIDArray: JsonArray;
        AdditionalAccountIDObject: JsonObject;
        AccountingCustomerPartyArray: JsonArray;
        AccountingCustomerPartyObject: JsonObject;
        CustomerPartyObject: JsonObject;
        CustomerPartyIdentificationArray: JsonArray;
        CustomerPartyIdentificationObject: JsonObject;
        CustomerIDObject: JsonObject;
        CustomerSchemeIDObject: JsonObject;
        CustomerBRNObject: JsonObject;
        CustomerID2Object: JsonObject;
        CustomerSchemeID2Object: JsonObject;
        CustomerSSTObject: JsonObject;
        CustomerID3Object: JsonObject;
        CustomerSchemeID3Object: JsonObject;
        CustomerTTXObject: JsonObject;
        CustomerID4Object: JsonObject;
        CustomerSchemeID4Object: JsonObject;
        CustomerPostalAddressArray: JsonArray;
        CustomerPostalAddressObject: JsonObject;
        CustomerCityNameArray: JsonArray;
        CustomerCityNameObject: JsonObject;
        CustomerPostalZoneArray: JsonArray;
        CustomerPostalZoneObject: JsonObject;
        CustomerCountrySubentityCodeArray: JsonArray;
        CustomerCountrySubentityCodeObject: JsonObject;
        CustomerAddressLineArray: JsonArray;
        CustomerAddressLineObject: JsonObject;
        CustomerLineArray: JsonArray;
        CustomerLineObject: JsonObject;
        CustomerCountryArray: JsonArray;
        CustomerCountryObject: JsonObject;
        CustomerIdentificationCodeArray: JsonArray;
        CustomerIdentificationCodeObject: JsonObject;
        CustomerPartyLegalEntityArray: JsonArray;
        CustomerPartyLegalEntityObject: JsonObject;
        CustomerRegistrationNameArray: JsonArray;
        CustomerRegistrationNameObject: JsonObject;
        CustomerContactArray: JsonArray;
        CustomerContactObject: JsonObject;
        CustomerTelephoneArray: JsonArray;
        CustomerTelephoneObject: JsonObject;
        CustomerElectronicMailArray: JsonArray;
        CustomerElectronicMailObject: JsonObject;
        DeliveryArray: JsonArray;
        DeliveryObject: JsonObject;
        DeliveryPartyArray: JsonArray;
        DeliveryPartyObject: JsonObject;
        DeliveryPartyLegalEntityArray: JsonArray;
        DeliveryPartyLegalEntityObject: JsonObject;
        DeliveryRegistrationNameArray: JsonArray;
        DeliveryRegistrationNameObject: JsonObject;
        DeliveryPostalAddressArray: JsonArray;
        DeliveryPostalAddressObject: JsonObject;
        DeliveryCityNameArray: JsonArray;
        DeliveryCityNameObject: JsonObject;
        DeliveryPostalZoneArray: JsonArray;
        DeliveryPostalZoneObject: JsonObject;
        DeliveryCountrySubentityCodeArray: JsonArray;
        DeliveryCountrySubentityCodeObject: JsonObject;
        DeliveryAddressLineArray: JsonArray;
        DeliveryAddressLineObject: JsonObject;
        DeliveryLineArray: JsonArray;
        DeliveryLineObject: JsonObject;
        DeliveryCountryArray: JsonArray;
        DeliveryCountryObject: JsonObject;
        DeliveryIdentificationCodeArray: JsonArray;
        DeliveryIdentificationCodeObject: JsonObject;
        DeliveryPartyIdentificationArray: JsonArray;
        DeliveryPartyIdentificationObject: JsonObject;
        DeliveryIDObject: JsonObject;
        DeliverySchemeIDObject: JsonObject;
        DeliveryBRNObject: JsonObject;
        DeliveryID2Object: JsonObject;
        DeliverySchemeID2Object: JsonObject;
        ShipmentArray: JsonArray;
        ShipmentObject: JsonObject;
        ShipmentIDArray: JsonArray;
        ShipmentIDObject: JsonObject;
        FreightAllowanceChargeArray: JsonArray;
        FreightAllowanceChargeObject: JsonObject;
        ChargeIndicatorArray: JsonArray;
        ChargeIndicatorObject: JsonObject;
        AllowanceChargeReasonArray: JsonArray;
        AllowanceChargeReasonObject: JsonObject;
        AmountArray: JsonArray;
        AmountObject: JsonObject;
        PaymentMeansArray: JsonArray;
        PaymentMeansObject: JsonObject;
        PaymentMeansCodeArray: JsonArray;
        PaymentMeansCodeObject: JsonObject;
        PayeeFinancialAccountArray: JsonArray;
        PayeeFinancialAccountObject: JsonObject;
        PayeeIDArray: JsonArray;
        PayeeIDObject: JsonObject;
        PaymentTermsArray: JsonArray;
        PaymentTermsObject: JsonObject;
        NoteArray: JsonArray;
        NoteObject: JsonObject;
        PrepaidPaymentArray: JsonArray;
        PrepaidPaymentObject: JsonObject;
        PrepaidIDArray: JsonArray;
        PrepaidIDObject: JsonObject;
        PaidAmountArray: JsonArray;
        PaidAmountObject: JsonObject;
        PaidDateArray: JsonArray;
        PaidDateObject: JsonObject;
        PaidTimeArray: JsonArray;
        PaidTimeObject: JsonObject;
        AllowanceChargeArray: JsonArray;
        AllowanceChargeObject: JsonObject;
        AllowanceChargeIndicatorArray: JsonArray;
        AllowanceChargeIndicatorObject: JsonObject;
        AllowanceChargeReason2Array: JsonArray;
        AllowanceChargeReason2Object: JsonObject;
        AllowanceChargeAmountArray: JsonArray;
        AllowanceChargeAmountObject: JsonObject;
        AllowanceChargeIndicator2Array: JsonArray;
        AllowanceChargeIndicator2Object: JsonObject;
        AllowanceChargeReason3Array: JsonArray;
        AllowanceChargeReason3Object: JsonObject;
        AllowanceChargeAmount2Array: JsonArray;
        AllowanceChargeAmount2Object: JsonObject;
        TaxTotalArray: JsonArray;
        TaxTotalObject: JsonObject;
        TaxAmountArray: JsonArray;
        TaxAmountObject: JsonObject;
        TaxSubtotalArray: JsonArray;
        TaxSubtotalObject: JsonObject;
        TaxableAmountArray: JsonArray;
        TaxableAmountObject: JsonObject;
        TaxAmount2Array: JsonArray;
        TaxAmount2Object: JsonObject;
        TaxCategoryArray: JsonArray;
        TaxCategoryObject: JsonObject;
        TaxCategoryIDArray: JsonArray;
        TaxCategoryIDObject: JsonObject;
        TaxSchemeArray: JsonArray;
        TaxSchemeObject: JsonObject;
        TaxSchemeIDArray: JsonArray;
        TaxSchemeIDObject: JsonObject;
        LegalMonetaryTotalArray: JsonArray;
        LegalMonetaryTotalObject: JsonObject;
        LineExtensionAmountArray: JsonArray;
        LineExtensionAmountObject: JsonObject;
        TaxExclusiveAmountArray: JsonArray;
        TaxExclusiveAmountObject: JsonObject;
        TaxInclusiveAmountArray: JsonArray;
        TaxInclusiveAmountObject: JsonObject;
        AllowanceTotalAmountArray: JsonArray;
        AllowanceTotalAmountObject: JsonObject;
        ChargeTotalAmountArray: JsonArray;
        ChargeTotalAmountObject: JsonObject;
        PayableRoundingAmountArray: JsonArray;
        PayableRoundingAmountObject: JsonObject;
        PayableAmountArray: JsonArray;
        PayableAmountObject: JsonObject;
    begin
        // ID
        IDObject.Add('_', SalesCrMemoHeader."No.");
        IDArray.Add(IDObject);
        InvoiceObject.Add('ID', IDArray);

        // Issue Date
        IssueDateObject.Add('_', Format(CalcDate('-1D', Today()), 0, '<Year4>-<Month,2>-<Day,2>'));
        IssueDateArray.Add(IssueDateObject);
        InvoiceObject.Add('IssueDate', IssueDateArray);

        // Issue Time
        IssueTimeObject.Add('_', Format(DT2Time(CurrentDateTime - 300000), 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        IssueTimeArray.Add(IssueTimeObject);
        InvoiceObject.Add('IssueTime', IssueTimeArray);

        // Invoice Type Code (02 = Credit Note)
        InvoiceTypeCodeObject.Add('_', '02');
        InvoiceTypeCodeObject.Add('listVersionID', '1.1');
        InvoiceTypeCodeArray.Add(InvoiceTypeCodeObject);
        InvoiceObject.Add('InvoiceTypeCode', InvoiceTypeCodeArray);

        // Document Currency Code
        DocumentCurrencyCodeObject.Add('_', GetDocumentCurrencyCode(SalesCrMemoHeader));
        DocumentCurrencyCodeArray.Add(DocumentCurrencyCodeObject);
        InvoiceObject.Add('DocumentCurrencyCode', DocumentCurrencyCodeArray);

        // Tax Currency Code
        TaxCurrencyCodeObject.Add('_', GetDocumentCurrencyCode(SalesCrMemoHeader));
        TaxCurrencyCodeArray.Add(TaxCurrencyCodeObject);
        InvoiceObject.Add('TaxCurrencyCode', TaxCurrencyCodeArray);

        // Invoice Period
        StartDateObject.Add('_', Format(CalcDate('-30D', SalesCrMemoHeader."Posting Date"), 0, '<Year4>-<Month,2>-<Day,2>'));
        StartDateArray.Add(StartDateObject);
        InvoicePeriodObject.Add('StartDate', StartDateArray);

        EndDateObject.Add('_', Format(SalesCrMemoHeader."Posting Date", 0, '<Year4>-<Month,2>-<Day,2>'));
        EndDateArray.Add(EndDateObject);
        InvoicePeriodObject.Add('EndDate', EndDateArray);

        DescriptionObject.Add('_', 'Monthly');
        DescriptionArray.Add(DescriptionObject);
        InvoicePeriodObject.Add('Description', DescriptionArray);

        InvoicePeriodArray.Add(InvoicePeriodObject);
        InvoiceObject.Add('InvoicePeriod', InvoicePeriodArray);

        // Billing Reference (Credit Note structure with both invoice reference and additional document reference)
        // First billing reference: Invoice Document Reference
        if SalesCrMemoHeader."Applies-to Doc. No." <> '' then begin
            // Invoice Document Reference
            ID2Object.Add('_', SalesCrMemoHeader."Applies-to Doc. No.");
            InvoiceDocumentReferenceObject.Add('ID', ID2Object);

            UUIDObject.Add('_', 'Reference Invoice UUID'); // This should be the actual UUID
            InvoiceDocumentReferenceObject.Add('UUID', UUIDObject);

            InvoiceDocumentReferenceArray.Add(InvoiceDocumentReferenceObject);
            BillingReferenceObject.Add('InvoiceDocumentReference', InvoiceDocumentReferenceArray);
            BillingReferenceArray.Add(BillingReferenceObject);
        end;

        // Second billing reference: Additional Document Reference
        Clear(BillingReferenceObject);
        ID3Object.Add('_', 'E12345678912');
        AdditionalDocumentReferenceObject.Add('ID', ID3Object);

        DocumentTypeObject.Add('_', 'CustomsImportForm');
        AdditionalDocumentReferenceObject.Add('DocumentType', DocumentTypeObject);

        AdditionalDocumentReferenceArray.Add(AdditionalDocumentReferenceObject);
        BillingReferenceObject.Add('AdditionalDocumentReference', AdditionalDocumentReferenceArray);
        BillingReferenceArray.Add(BillingReferenceObject);

        // Add the complete billing reference array to the invoice object
        InvoiceObject.Add('BillingReference', BillingReferenceArray);

        // Accounting Supplier Party
        BuildSupplierPartyStructure(PartyObject, CompanyInfo);
        AccountingSupplierPartyObject.Add('Party', PartyObject);

        // Additional Account ID
        AdditionalAccountIDObject.Add('_', 'CPT-CCN-W-211111-KL-000002');
        AdditionalAccountIDObject.Add('schemeAgencyName', 'CertEX');
        AdditionalAccountIDArray.Add(AdditionalAccountIDObject);
        AccountingSupplierPartyObject.Add('AdditionalAccountID', AdditionalAccountIDArray);

        AccountingSupplierPartyArray.Add(AccountingSupplierPartyObject);
        InvoiceObject.Add('AccountingSupplierParty', AccountingSupplierPartyArray);

        // Accounting Customer Party
        BuildCustomerPartyStructure(CustomerPartyObject, Customer);
        AccountingCustomerPartyObject.Add('Party', CustomerPartyObject);
        AccountingCustomerPartyArray.Add(AccountingCustomerPartyObject);
        InvoiceObject.Add('AccountingCustomerParty', AccountingCustomerPartyArray);

        // Delivery
        BuildDeliveryStructure(DeliveryObject, Customer);
        DeliveryArray.Add(DeliveryObject);
        InvoiceObject.Add('Delivery', DeliveryArray);

        // Payment Means
        PaymentMeansCodeObject.Add('_', '03');
        PaymentMeansCodeArray.Add(PaymentMeansCodeObject);
        PaymentMeansObject.Add('PaymentMeansCode', PaymentMeansCodeArray);

        PayeeIDObject.Add('_', '1234567890123');
        PayeeFinancialAccountObject.Add('ID', PayeeIDObject);
        PayeeFinancialAccountArray.Add(PayeeFinancialAccountObject);
        PaymentMeansObject.Add('PayeeFinancialAccount', PayeeFinancialAccountArray);

        PaymentMeansArray.Add(PaymentMeansObject);
        InvoiceObject.Add('PaymentMeans', PaymentMeansArray);

        // Payment Terms
        NoteObject.Add('_', 'Payment method is cash');
        NoteArray.Add(NoteObject);
        PaymentTermsObject.Add('Note', NoteArray);
        PaymentTermsArray.Add(PaymentTermsObject);
        InvoiceObject.Add('PaymentTerms', PaymentTermsArray);

        // Prepaid Payment
        PrepaidIDObject.Add('_', '');
        PrepaidIDArray.Add(PrepaidIDObject);
        PrepaidPaymentObject.Add('ID', PrepaidIDArray);

        PaidAmountObject.Add('_', 0.0);
        PaidAmountObject.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoHeader));
        PaidAmountArray.Add(PaidAmountObject);
        PrepaidPaymentObject.Add('PaidAmount', PaidAmountArray);

        PaidDateObject.Add('_', '');
        PaidDateArray.Add(PaidDateObject);
        PrepaidPaymentObject.Add('PaidDate', PaidDateArray);

        PaidTimeObject.Add('_', '');
        PaidTimeArray.Add(PaidTimeObject);
        PrepaidPaymentObject.Add('PaidTime', PaidTimeArray);

        PrepaidPaymentArray.Add(PrepaidPaymentObject);
        InvoiceObject.Add('PrepaidPayment', PrepaidPaymentArray);

        // Allowance Charge
        BuildAllowanceChargeStructure(AllowanceChargeArray);
        InvoiceObject.Add('AllowanceCharge', AllowanceChargeArray);

        // Tax Total
        BuildTaxTotalStructure(TaxTotalObject, TotalAmount, TotalTaxAmount);
        TaxTotalArray.Add(TaxTotalObject);
        InvoiceObject.Add('TaxTotal', TaxTotalArray);

        // Legal Monetary Total
        BuildLegalMonetaryTotalStructure(LegalMonetaryTotalObject, TotalAmount, TotalTaxAmount);
        LegalMonetaryTotalArray.Add(LegalMonetaryTotalObject);
        InvoiceObject.Add('LegalMonetaryTotal', LegalMonetaryTotalArray);
    end;

    /// <summary>
    /// Initialize UBL structure specifically for Credit Note documents
    /// </summary>
    /// <param name="UBLDocument">The UBL document to initialize</param>
    local procedure InitializeCreditMemoUBLStructure(var UBLDocument: JsonObject)
    var
        NamespaceObject: JsonObject;
    begin
        // Set UBL namespace and schema information for Credit Note (following myinvois standards)
        UBLDocument.Add('_declaration', CreateXMLDeclaration());
        UBLDocument.Add('CreditNote', CreateCreditNoteRoot());
    end;

    /// <summary>
    /// Create Credit Note root element with proper UBL 2.1 namespaces
    /// </summary>
    /// <returns>Credit Note root object with namespaces</returns>
    local procedure CreateCreditNoteRoot() CreditNoteRoot: JsonObject
    var
        AttributesObject: JsonObject;
    begin
        // UBL Credit Note root element with required namespaces
        AttributesObject.Add('xmlns', 'urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2');
        AttributesObject.Add('xmlns:cac', 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2');
        AttributesObject.Add('xmlns:cbc', 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2');

        CreditNoteRoot.Add('_attributes', AttributesObject);
    end;

    local procedure BuildCreditMemoIdentification(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        UBLVersionID: JsonObject;
        CustomizationID: JsonObject;
        ProfileID: JsonObject;
        ID: JsonObject;
        IssueDate: JsonObject;
        IssueTime: JsonObject;
        InvoiceTypeCode: JsonObject;
        DocumentCurrencyCode: JsonObject;
        InvoiceTypeCodeAttributes: JsonObject;
    begin
        // Get Credit Note object from UBL structure
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // UBL Version (required by myinvois)
        UBLVersionID.Add('_text', '2.1');
        CreditNoteObject.Add('cbc:UBLVersionID', UBLVersionID);

        // Customization ID (Malaysia e-Invoice specific)
        CustomizationID.Add('_text', 'MY:1.0');
        CreditNoteObject.Add('cbc:CustomizationID', CustomizationID);

        // Profile ID (Malaysia e-Invoice profile)
        ProfileID.Add('_text', 'reporting:1.0');
        CreditNoteObject.Add('cbc:ProfileID', ProfileID);

        // Credit Memo Number
        ID.Add('_text', SalesCrMemoHeader."No.");
        CreditNoteObject.Add('cbc:ID', ID);

        // FORCE: Always use yesterday's date to ensure it's never in the future
        IssueDate.Add('_text', Format(CalcDate('-1D', Today()), 0, '<Year4>-<Month,2>-<Day,2>'));
        CreditNoteObject.Add('cbc:IssueDate', IssueDate);

        IssueTime.Add('_text', Format(DT2Time(CurrentDateTime - 300000), 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        CreditNoteObject.Add('cbc:IssueTime', IssueTime);

        // CRITICAL: Correct InvoiceTypeCode for credit notes
        InvoiceTypeCode.Add('_text', '02'); // Credit Note
        InvoiceTypeCodeAttributes.Add('listVersionID', '1.1'); // LHDN v1.1 requirement
        InvoiceTypeCode.Add('_attributes', InvoiceTypeCodeAttributes);
        CreditNoteObject.Add('cbc:InvoiceTypeCode', InvoiceTypeCode);

        // Document Currency Code
        DocumentCurrencyCode.Add('_text', GetDocumentCurrencyCode(SalesCrMemoHeader));
        CreditNoteObject.Add('cbc:DocumentCurrencyCode', DocumentCurrencyCode);

        // ADDED: Tax Currency Code (required by LHDN)
        CreditNoteObject.Add('cbc:TaxCurrencyCode', DocumentCurrencyCode);

        // Update the document
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    local procedure BuildCreditMemoLines(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        CreditNoteLinesArray: JsonArray;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
    begin
        // Get Credit Note object from UBL structure
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Build credit note lines array
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        if SalesCrMemoLine.FindSet() then
            repeat
                BuildSingleCreditMemoLine(CreditNoteLinesArray, SalesCrMemoLine);
            until SalesCrMemoLine.Next() = 0;

        // FIXED: LHDN expects InvoiceLine even for credit memos
        CreditNoteObject.Add('cac:InvoiceLine', CreditNoteLinesArray);

        // Update the document
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    local procedure BuildSingleCreditMemoLine(var CreditNoteLinesArray: JsonArray; SalesCrMemoLine: Record "Sales Cr.Memo Line")
    var
        CreditNoteLineObject: JsonObject;
        ID: JsonObject;
        InvoicedQuantity: JsonObject;
        LineExtensionAmount: JsonObject;
        Item: JsonObject;
        ItemDescription: JsonObject;
        Name: JsonObject;
        SellersItemIdentification: JsonObject;
        ID2: JsonObject;
        Price: JsonObject;
        PriceAmount: JsonObject;
        TaxTotal: JsonObject;
        TaxSubtotal: JsonObject;
        TaxCategory: JsonObject;
        TaxScheme: JsonObject;
        TaxAmount: Decimal;
        LineTaxAmount: JsonObject;
        LineTaxableAmount: JsonObject;
        LineTaxSubtotalAmount: JsonObject;
    begin
        // CORRECTED: Use positive amounts for credit notes
        TaxAmount := SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine."Line Amount";

        // Credit Note Line ID
        ID.Add('_text', Format(SalesCrMemoLine."Line No."));
        CreditNoteLineObject.Add('cbc:ID', ID);

        // CORRECTED: Use positive quantity for credit memo (LHDN expects positive values)
        InvoicedQuantity.Add('_text', Format(SalesCrMemoLine.Quantity));
        InvoicedQuantity.Add('unitCode', 'C62');
        CreditNoteLineObject.Add('cbc:InvoicedQuantity', InvoicedQuantity);

        // CORRECTED: Use positive line amount
        LineExtensionAmount.Add('_text', Format(SalesCrMemoLine."Line Amount"));
        LineExtensionAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        CreditNoteLineObject.Add('cbc:LineExtensionAmount', LineExtensionAmount);

        // Add Tax Total for this line
        LineTaxAmount.Add('_text', Format(TaxAmount));
        LineTaxAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        TaxTotal.Add('cbc:TaxAmount', LineTaxAmount);

        // Tax Subtotal
        LineTaxableAmount.Add('_text', Format(SalesCrMemoLine."Line Amount"));
        LineTaxableAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        TaxSubtotal.Add('cbc:TaxableAmount', LineTaxableAmount);

        LineTaxSubtotalAmount.Add('_text', Format(TaxAmount));
        LineTaxSubtotalAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        TaxSubtotal.Add('cbc:TaxAmount', LineTaxSubtotalAmount);

        // Tax Category
        TaxCategory.Add('cbc:ID', 'S'); // Standard rate
        TaxCategory.Add('cbc:Percent', Format(SalesCrMemoLine."VAT %"));

        // ADDED: Tax Exemption Reason (required by LHDN)
        TaxCategory.Add('cbc:TaxExemptionReason', BuildTaxExemptionReason());

        // Tax Scheme
        TaxScheme.Add('cbc:ID', 'OTH');
        TaxScheme.Add('schemeID', 'UN/ECE 5153');
        TaxScheme.Add('schemeAgencyID', '6'); // ADDED: Scheme Agency ID (required by LHDN)
        TaxCategory.Add('cac:TaxScheme', TaxScheme);
        TaxSubtotal.Add('cac:TaxCategory', TaxCategory);

        TaxTotal.Add('cac:TaxSubtotal', TaxSubtotal);
        CreditNoteLineObject.Add('cac:TaxTotal', TaxTotal);

        // Item Information
        Item.Add('cbc:Description', SalesCrMemoLine.Description);

        // ADDED: Commodity Classification (required by LHDN)
        Item.Add('cac:CommodityClassification', BuildCommodityClassification());

        // Item Name
        Name.Add('_text', SalesCrMemoLine.Description);
        ItemDescription.Add('cbc:Name', Name);
        Item.Add('cac:Description', ItemDescription);

        // Item ID
        ID2.Add('_text', SalesCrMemoLine."No.");
        SellersItemIdentification.Add('cbc:ID', ID2);
        Item.Add('cac:SellersItemIdentification', SellersItemIdentification);

        // ADDED: Origin Country (required by LHDN)
        Item.Add('cac:OriginCountry', BuildOriginCountry());

        // Price Information
        PriceAmount.Add('_text', Format(SalesCrMemoLine."Unit Price"));
        PriceAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        Price.Add('cbc:PriceAmount', PriceAmount);

        // ADDED: Item Price Extension (required by LHDN)
        CreditNoteLineObject.Add('cac:ItemPriceExtension', BuildItemPriceExtension(SalesCrMemoLine));

        // ADDED: Allowance Charge (required by LHDN)
        CreditNoteLineObject.Add('cac:AllowanceCharge', BuildAllowanceCharge(SalesCrMemoLine));

        // Add item and price to line
        CreditNoteLineObject.Add('cac:Item', Item);
        CreditNoteLineObject.Add('cac:Price', Price);

        // Add line to array
        CreditNoteLinesArray.Add(CreditNoteLineObject);
    end;

    // Enhanced helper method for credit memo currency code
    local procedure GetDocumentCurrencyCode(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Text
    begin
        if SalesCrMemoHeader."Currency Code" <> '' then
            exit(SalesCrMemoHeader."Currency Code")
        else
            exit('MYR'); // Default Malaysian Ringgit
    end;

    local procedure GetDocumentCurrencyCode(SalesCrMemoLine: Record "Sales Cr.Memo Line"): Text
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
    begin
        if SalesCrMemoHeader.Get(SalesCrMemoLine."Document No.") then
            exit(GetDocumentCurrencyCode(SalesCrMemoHeader))
        else
            exit('MYR');
    end;

    // Enhanced credit memo document building with proper structure
    procedure BuildEnhancedCreditMemoDocument(SalesCrMemoHeader: Record "Sales Cr.Memo Header") UBLDocument: JsonObject
    var
        CompanyInfo: Record "Company Information";
        Customer: Record Customer;
        TotalAmount: Decimal;
        TotalTaxAmount: Decimal;
    begin
        CompanyInfo.Get();
        Customer.Get(SalesCrMemoHeader."Sell-to Customer No.");

        // Calculate totals
        CalculateCreditMemoTotals(SalesCrMemoHeader, TotalAmount, TotalTaxAmount);

        // FIXED: LHDN expects credit memos to use Invoice structure, not CreditNote
        InitializeUBLStructure(UBLDocument);

        // Build core credit memo identification using Invoice structure
        BuildCreditMemoIdentificationAsInvoice(UBLDocument, SalesCrMemoHeader);

        // Build billing reference for original invoice (LHDN v1.1 requirement)
        BuildCreditMemoBillingReferenceAsInvoice(UBLDocument, SalesCrMemoHeader);

        // Build parties (supplier and customer) - these already work with Invoice structure
        BuildSupplierPartyAsInvoice(UBLDocument, SalesCrMemoHeader);
        BuildCustomerPartyAsInvoice(UBLDocument, SalesCrMemoHeader);

        // Build credit memo lines using Invoice structure
        BuildCreditMemoLinesAsInvoice(UBLDocument, SalesCrMemoHeader);

        // Build Document-level Legal Monetary Total (required by LHDN)
        BuildDocumentLevelLegalMonetaryTotalAsInvoice(UBLDocument, SalesCrMemoHeader);

        // Build Document-level Tax Total (required by LHDN)
        BuildDocumentLevelTaxTotalAsInvoice(UBLDocument, SalesCrMemoHeader);

        // Validate final document structure
        if not ValidateUBLDocument(UBLDocument) then
            Error('Credit Memo UBL Document validation failed\\Please check document structure and required fields.');
    end;

    // Enhanced Legal Monetary Total for credit memos
    local procedure BuildLegalMonetaryTotal(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header"; TotalAmount: Decimal; TotalTaxAmount: Decimal)
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        LegalMonetaryTotal: JsonObject;
        LineExtensionAmount: JsonObject;
        TaxExclusiveAmount: JsonObject;
        TaxInclusiveAmount: JsonObject;
        PayableAmount: JsonObject;
        CurrencyCode: Text;
    begin
        CurrencyCode := GetDocumentCurrencyCode(SalesCrMemoHeader);

        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Line Extension Amount (negative for credit note)
        LineExtensionAmount.Add('_text', Format(TotalAmount));
        LineExtensionAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:LineExtensionAmount', LineExtensionAmount);

        // Tax Exclusive Amount (negative for credit note)
        TaxExclusiveAmount.Add('_text', Format(TotalAmount));
        TaxExclusiveAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:TaxExclusiveAmount', TaxExclusiveAmount);

        // Tax Inclusive Amount (negative for credit note)
        TaxInclusiveAmount.Add('_text', Format(TotalAmount + TotalTaxAmount));
        TaxInclusiveAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:TaxInclusiveAmount', TaxInclusiveAmount);

        // Payable Amount (negative for credit note)
        PayableAmount.Add('_text', Format(TotalAmount + TotalTaxAmount));
        PayableAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:PayableAmount', PayableAmount);

        CreditNoteObject.Add('cac:LegalMonetaryTotal', LegalMonetaryTotal);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Build additional document reference (required by LHDN)
    local procedure BuildAdditionalDocumentReference(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        AdditionalDocumentReference: JsonObject;
        ID: JsonObject;
        DocumentType: JsonObject;  // ✅ ADD THIS
    begin
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Add additional document reference with credit memo number
        ID.Add('_text', SalesCrMemoHeader."No.");
        AdditionalDocumentReference.Add('cbc:ID', ID);

        // ✅ ADD THESE 2 LINES:
        DocumentType.Add('_text', 'CreditNote');
        AdditionalDocumentReference.Add('cbc:DocumentType', DocumentType);

        CreditNoteObject.Add('cac:AdditionalDocumentReference', AdditionalDocumentReference);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Build payment terms (required by LHDN)
    local procedure BuildPaymentTerms(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        PaymentTerms: JsonObject;
        Note: JsonObject;
    begin
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Add payment terms note
        Note.Add('_text', 'Credit Note - Payment terms as per original invoice');
        PaymentTerms.Add('cbc:Note', Note);

        CreditNoteObject.Add('cac:PaymentTerms', PaymentTerms);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Build delivery information (required by LHDN)
    local procedure BuildDeliveryInformation(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        Delivery: JsonObject;
        DeliveryParty: JsonObject;
        PartyLegalEntity: JsonObject;
        RegistrationName: JsonObject;
        PostalAddress: JsonObject;
        CityName: JsonObject;
        PostalZone: JsonObject;
        CountrySubentityCode: JsonObject;
        AddressLine: JsonObject;
        Line: JsonObject;
        Country: JsonObject;
        IdentificationCode: JsonObject;
        Customer: Record Customer;
    begin
        Customer.Get(SalesCrMemoHeader."Sell-to Customer No.");

        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Build delivery party structure
        RegistrationName.Add('_text', Customer.Name);
        PartyLegalEntity.Add('cbc:RegistrationName', RegistrationName);
        DeliveryParty.Add('cac:PartyLegalEntity', PartyLegalEntity);

        // Build delivery address
        CityName.Add('_text', Customer.City);
        PostalAddress.Add('cbc:CityName', CityName);

        PostalZone.Add('_text', Customer."Post Code");
        PostalAddress.Add('cbc:PostalZone', PostalZone);

        CountrySubentityCode.Add('_text', Customer."Country/Region Code");
        PostalAddress.Add('cbc:CountrySubentityCode', CountrySubentityCode);

        Line.Add('_text', Customer.Address);
        AddressLine.Add('cbc:Line', Line);
        PostalAddress.Add('cac:AddressLine', AddressLine);

        IdentificationCode.Add('_text', Customer."Country/Region Code");
        Country.Add('cbc:IdentificationCode', IdentificationCode);
        PostalAddress.Add('cac:Country', Country);

        DeliveryParty.Add('cac:PostalAddress', PostalAddress);
        Delivery.Add('cac:DeliveryParty', DeliveryParty);

        CreditNoteObject.Add('cac:Delivery', Delivery);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Build payment means (required by LHDN)
    local procedure BuildPaymentMeans(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        PaymentMeans: JsonObject;
        PaymentMeansCode: JsonObject;
        PayeeFinancialAccount: JsonObject;
        ID: JsonObject;
    begin
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Payment means code (01 = Credit Transfer)
        PaymentMeansCode.Add('_text', '01');
        PaymentMeans.Add('cbc:PaymentMeansCode', PaymentMeansCode);

        // Payee financial account
        ID.Add('_text', 'AMB'); // Default bank code
        PayeeFinancialAccount.Add('cbc:ID', ID);
        PaymentMeans.Add('cac:PayeeFinancialAccount', PayeeFinancialAccount);

        CreditNoteObject.Add('cac:PaymentMeans', PaymentMeans);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Build shipment information (required by LHDN)
    local procedure BuildShipmentInformation(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        Shipment: JsonObject;
        ID: JsonObject;
        FreightAllowanceCharge: JsonObject;
        ChargeIndicator: JsonObject;
        AllowanceChargeReason: JsonObject;
        Amount: JsonObject;
    begin
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Shipment ID
        ID.Add('_text', 'SHIP-EXT-TEST');
        Shipment.Add('cbc:ID', ID);

        // Freight allowance charge
        ChargeIndicator.Add('_text', false);
        FreightAllowanceCharge.Add('cbc:ChargeIndicator', ChargeIndicator);

        AllowanceChargeReason.Add('_text', '');
        FreightAllowanceCharge.Add('cbc:AllowanceChargeReason', AllowanceChargeReason);

        Amount.Add('_text', 0.0);
        Amount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoHeader));
        FreightAllowanceCharge.Add('cbc:Amount', Amount);

        Shipment.Add('cac:FreightAllowanceCharge', FreightAllowanceCharge);

        CreditNoteObject.Add('cac:Shipment', Shipment);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Build invoice period (required by LHDN)
    local procedure BuildInvoicePeriod(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        InvoicePeriod: JsonObject;
        StartDate: JsonObject;
        EndDate: JsonObject;
        Description: JsonObject;
    begin
        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Start date (30 days before issue date)
        StartDate.Add('_text', Format(CalcDate('-30D', SalesCrMemoHeader."Posting Date"), 0, '<Year4>-<Month,2>-<Day,2>'));
        InvoicePeriod.Add('cbc:StartDate', StartDate);

        // End date (issue date)
        EndDate.Add('_text', Format(SalesCrMemoHeader."Posting Date", 0, '<Year4>-<Month,2>-<Day,2>'));
        InvoicePeriod.Add('cbc:EndDate', EndDate);

        // Description
        Description.Add('_text', 'Monthly');
        InvoicePeriod.Add('cbc:Description', Description);

        CreditNoteObject.Add('cac:InvoicePeriod', InvoicePeriod);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Build item price extension (required by LHDN)
    local procedure BuildItemPriceExtension(SalesCrMemoLine: Record "Sales Cr.Memo Line") ItemPriceExtension: JsonObject
    var
        Amount: JsonObject;
    begin
        // Line amount
        Amount.Add('_text', Format(SalesCrMemoLine."Line Amount"));
        Amount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        ItemPriceExtension.Add('cbc:Amount', Amount);
    end;

    // ADDED: Build commodity classification (required by LHDN)
    local procedure BuildCommodityClassification() CommodityClassification: JsonObject
    var
        ItemClassificationCode: JsonObject;
        ItemClassificationCode2: JsonObject;
        ItemClassificationCodeArray: JsonArray;
    begin
        // PTC classification code
        ItemClassificationCode.Add('_text', '022');
        ItemClassificationCode.Add('listID', 'PTC');
        ItemClassificationCodeArray.Add(ItemClassificationCode);

        // CLASS classification code
        ItemClassificationCode2.Add('_text', '06');
        ItemClassificationCode2.Add('listID', 'CLASS');
        ItemClassificationCodeArray.Add(ItemClassificationCode2);

        // Add the array to commodity classification
        CommodityClassification.Add('cbc:ItemClassificationCode', ItemClassificationCodeArray);
    end;

    // ADDED: Build origin country (required by LHDN)
    local procedure BuildOriginCountry() OriginCountry: JsonObject
    var
        IdentificationCode: JsonObject;
    begin
        // Malaysia country code
        IdentificationCode.Add('_text', 'MYS');
        OriginCountry.Add('cbc:IdentificationCode', IdentificationCode);
    end;

    // ADDED: Build allowance charge (required by LHDN)
    local procedure BuildAllowanceCharge(SalesCrMemoLine: Record "Sales Cr.Memo Line") AllowanceCharge: JsonObject
    var
        ChargeIndicator: JsonObject;
        AllowanceChargeReason: JsonObject;
        MultiplierFactorNumeric: JsonObject;
        Amount: JsonObject;
    begin
        // Charge indicator (false = allowance, true = charge)
        ChargeIndicator.Add('_text', false);
        AllowanceCharge.Add('cbc:ChargeIndicator', ChargeIndicator);

        // Allowance charge reason
        AllowanceChargeReason.Add('_text', 'Sample Description');
        AllowanceCharge.Add('cbc:AllowanceChargeReason', AllowanceChargeReason);

        // Multiplier factor (0.15 = 15%)
        MultiplierFactorNumeric.Add('_text', 0.15);
        AllowanceCharge.Add('cbc:MultiplierFactorNumeric', MultiplierFactorNumeric);

        // Amount
        Amount.Add('_text', 100);
        Amount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        AllowanceCharge.Add('cbc:Amount', Amount);
    end;

    // ADDED: Build tax exemption reason (required by LHDN)
    local procedure BuildTaxExemptionReason() TaxExemptionReason: JsonObject
    begin
        // Tax exemption reason for standard rate
        TaxExemptionReason.Add('_text', 'Standard Rate');
    end;

    // Enhanced Tax Total for credit memos
    local procedure BuildTaxTotal(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header"; TotalTaxAmount: Decimal)
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        TaxTotal: JsonObject;
        TaxSubtotal: JsonObject;
        TaxCategory: JsonObject;
        TaxScheme: JsonObject;
        TaxAmount: JsonObject;
        TaxSubtotalTaxAmount: JsonObject;
        TaxableAmount: JsonObject;
        CurrencyCode: Text;
    begin
        CurrencyCode := GetDocumentCurrencyCode(SalesCrMemoHeader);

        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Tax Amount for TaxTotal (negative for credit note)
        TaxAmount.Add('_text', Format(TotalTaxAmount));
        TaxAmount.Add('currencyID', CurrencyCode);
        TaxTotal.Add('cbc:TaxAmount', TaxAmount);

        // Tax Subtotal
        TaxableAmount.Add('_text', Format(-SalesCrMemoHeader."Amount"));
        TaxableAmount.Add('currencyID', CurrencyCode);
        TaxSubtotal.Add('cbc:TaxableAmount', TaxableAmount);

        // Tax Amount for TaxSubtotal (negative for credit note)
        TaxSubtotalTaxAmount.Add('_text', Format(TotalTaxAmount));
        TaxSubtotalTaxAmount.Add('currencyID', CurrencyCode);
        TaxSubtotal.Add('cbc:TaxAmount', TaxSubtotalTaxAmount);

        // Tax Category
        TaxCategory.Add('cbc:ID', 'S'); // Standard rate
        TaxCategory.Add('cbc:Percent', '10'); // Default VAT rate

        // Tax Scheme
        TaxScheme.Add('cbc:ID', 'OTH');
        TaxScheme.Add('schemeID', 'UN/ECE 5153');
        TaxScheme.Add('schemeAgencyID', '6'); // ADDED: Scheme Agency ID (required by LHDN)
        TaxCategory.Add('cac:TaxScheme', TaxScheme);
        TaxSubtotal.Add('cac:TaxCategory', TaxCategory);

        TaxTotal.Add('cac:TaxSubtotal', TaxSubtotal);
        CreditNoteObject.Add('cac:TaxTotal', TaxTotal);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADD: Billing Reference (Required for credit notes)
    local procedure BuildCreditMemoBillingReference(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        BillingReferenceArray: JsonArray;
        BillingReferenceObject: JsonObject;
        InvoiceDocumentReferenceArray: JsonArray;
        InvoiceDocumentReferenceObject: JsonObject;
        IDObject: JsonObject;
        UUIDObject: JsonObject;
        eInvoiceSubmissionLog: Record "eInvoice Submission Log";
        OriginalInvoiceUUID: Text;
    begin
        if SalesCrMemoHeader."Applies-to Doc. No." = '' then
            exit;

        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Try to find the original invoice UUID from submission log
        eInvoiceSubmissionLog.SetRange("Invoice No.", SalesCrMemoHeader."Applies-to Doc. No.");
        eInvoiceSubmissionLog.SetRange(Status, 'Valid');
        if eInvoiceSubmissionLog.FindLast() then
            OriginalInvoiceUUID := eInvoiceSubmissionLog."Document UUID"
        else
            OriginalInvoiceUUID := 'Reference Invoice UUID'; // Fallback

        // Reference to original invoice
        IDObject.Add('_', SalesCrMemoHeader."Applies-to Doc. No.");
        InvoiceDocumentReferenceObject.Add('ID', IDObject);

        // Add UUID if available from submission log
        UUIDObject.Add('_', OriginalInvoiceUUID);
        InvoiceDocumentReferenceObject.Add('UUID', UUIDObject);

        InvoiceDocumentReferenceArray.Add(InvoiceDocumentReferenceObject);
        BillingReferenceObject.Add('InvoiceDocumentReference', InvoiceDocumentReferenceArray);
        BillingReferenceArray.Add(BillingReferenceObject);

        CreditNoteObject.Add('BillingReference', BillingReferenceArray);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Document-level tax total (required by LHDN)
    local procedure BuildDocumentLevelTaxTotal(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        TaxTotal: JsonObject;
        TaxSubtotal: JsonObject;
        TaxCategory: JsonObject;
        TaxScheme: JsonObject;
        TaxAmount: JsonObject;
        TaxableAmount: JsonObject;
        CurrencyCode: Text;
        TotalTaxAmount: Decimal;
    begin
        CurrencyCode := GetDocumentCurrencyCode(SalesCrMemoHeader);
        TotalTaxAmount := SalesCrMemoHeader."Amount Including VAT" - SalesCrMemoHeader."Amount";

        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Document-level Tax Total
        TaxAmount.Add('_text', Format(TotalTaxAmount));
        TaxAmount.Add('currencyID', CurrencyCode);
        TaxTotal.Add('cbc:TaxAmount', TaxAmount);

        // Tax Subtotal
        TaxableAmount.Add('_text', Format(SalesCrMemoHeader."Amount"));
        TaxableAmount.Add('currencyID', CurrencyCode);
        TaxSubtotal.Add('cbc:TaxableAmount', TaxableAmount);

        // Tax Category
        TaxCategory.Add('cbc:ID', 'S'); // Standard rate
        TaxCategory.Add('cbc:Percent', '10'); // Default VAT rate

        // Tax Scheme
        TaxScheme.Add('cbc:ID', 'OTH');
        TaxScheme.Add('schemeID', 'UN/ECE 5153');
        TaxScheme.Add('schemeAgencyID', '6'); // ADDED: Scheme Agency ID (required by LHDN)
        TaxCategory.Add('cac:TaxScheme', TaxScheme);
        TaxSubtotal.Add('cac:TaxCategory', TaxCategory);

        TaxTotal.Add('cac:TaxSubtotal', TaxSubtotal);
        CreditNoteObject.Add('cac:TaxTotal', TaxTotal);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    // ADDED: Document-level legal monetary total (required by LHDN)
    local procedure BuildDocumentLevelLegalMonetaryTotal(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        CreditNoteToken: JsonToken;
        CreditNoteObject: JsonObject;
        LegalMonetaryTotal: JsonObject;
        LineExtensionAmount: JsonObject;
        TaxExclusiveAmount: JsonObject;
        TaxInclusiveAmount: JsonObject;
        PayableAmount: JsonObject;
        CurrencyCode: Text;
        TotalAmount: Decimal;
        TotalTaxAmount: Decimal;
    begin
        CurrencyCode := GetDocumentCurrencyCode(SalesCrMemoHeader);
        TotalAmount := SalesCrMemoHeader."Amount";
        TotalTaxAmount := SalesCrMemoHeader."Amount Including VAT" - SalesCrMemoHeader."Amount";

        UBLDocument.Get('CreditNote', CreditNoteToken);
        CreditNoteObject := CreditNoteToken.AsObject();

        // Line Extension Amount
        LineExtensionAmount.Add('_text', Format(TotalAmount));
        LineExtensionAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:LineExtensionAmount', LineExtensionAmount);

        // Tax Exclusive Amount
        TaxExclusiveAmount.Add('_text', Format(TotalAmount));
        TaxExclusiveAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:TaxExclusiveAmount', TaxExclusiveAmount);

        // Tax Inclusive Amount
        TaxInclusiveAmount.Add('_text', Format(TotalAmount + TotalTaxAmount));
        TaxInclusiveAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:TaxInclusiveAmount', TaxInclusiveAmount);

        // Payable Amount
        PayableAmount.Add('_text', Format(TotalAmount + TotalTaxAmount));
        PayableAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:PayableAmount', PayableAmount);

        CreditNoteObject.Add('cac:LegalMonetaryTotal', LegalMonetaryTotal);
        UBLDocument.Replace('CreditNote', CreditNoteObject);
    end;

    /// <summary>
    /// Builds the supplier party structure following the sample format
    /// </summary>
    local procedure BuildSupplierPartyStructure(var PartyObject: JsonObject; CompanyInfo: Record "Company Information")
    var
        IndustryClassificationCodeArray: JsonArray;
        IndustryClassificationCodeObject: JsonObject;
        PartyIdentificationArray: JsonArray;
        PartyIdentificationObject: JsonObject;
        IDObject: JsonObject;
        SchemeIDObject: JsonObject;
        BRNObject: JsonObject;
        ID2Object: JsonObject;
        SchemeID2Object: JsonObject;
        SSTObject: JsonObject;
        ID3Object: JsonObject;
        SchemeID3Object: JsonObject;
        TTXObject: JsonObject;
        ID4Object: JsonObject;
        SchemeID4Object: JsonObject;
        PostalAddressArray: JsonArray;
        PostalAddressObject: JsonObject;
        CityNameArray: JsonArray;
        CityNameObject: JsonObject;
        PostalZoneArray: JsonArray;
        PostalZoneObject: JsonObject;
        CountrySubentityCodeArray: JsonArray;
        CountrySubentityCodeObject: JsonObject;
        AddressLineArray: JsonArray;
        AddressLineObject: JsonObject;
        LineArray: JsonArray;
        LineObject: JsonObject;
        CountryArray: JsonArray;
        CountryObject: JsonObject;
        IdentificationCodeArray: JsonArray;
        IdentificationCodeObject: JsonObject;
        PartyLegalEntityArray: JsonArray;
        PartyLegalEntityObject: JsonObject;
        RegistrationNameArray: JsonArray;
        RegistrationNameObject: JsonObject;
        ContactArray: JsonArray;
        ContactObject: JsonObject;
        TelephoneArray: JsonArray;
        TelephoneObject: JsonObject;
        ElectronicMailArray: JsonArray;
        ElectronicMailObject: JsonObject;
    begin
        // Industry Classification Code
        IndustryClassificationCodeObject.Add('_', '13921');
        IndustryClassificationCodeObject.Add('name', 'Manufacture of made-up articles of any textile materials, including of knitted or crocheted fabrics');
        IndustryClassificationCodeArray.Add(IndustryClassificationCodeObject);
        PartyObject.Add('IndustryClassificationCode', IndustryClassificationCodeArray);

        // Party Identification - TIN
        IDObject.Add('_', CompanyInfo."Registration No.");
        IDObject.Add('schemeID', 'TIN');
        PartyIdentificationObject.Add('ID', IDObject);
        PartyIdentificationArray.Add(PartyIdentificationObject);

        // Party Identification - BRN
        BRNObject.Add('_', '199201007100');
        BRNObject.Add('schemeID', 'BRN');
        PartyIdentificationArray.Add(BRNObject);

        // Party Identification - SST
        SSTObject.Add('_', 'NA');
        SSTObject.Add('schemeID', 'SST');
        PartyIdentificationArray.Add(SSTObject);

        // Party Identification - TTX
        TTXObject.Add('_', 'NA');
        TTXObject.Add('schemeID', 'TTX');
        PartyIdentificationArray.Add(TTXObject);

        PartyObject.Add('PartyIdentification', PartyIdentificationArray);

        // Postal Address
        CityNameObject.Add('_', 'Kuala Lumpur');
        CityNameArray.Add(CityNameObject);
        PostalAddressObject.Add('CityName', CityNameArray);

        PostalZoneObject.Add('_', '50480');
        PostalZoneArray.Add(PostalZoneObject);
        PostalAddressObject.Add('PostalZone', PostalZoneArray);

        CountrySubentityCodeObject.Add('_', '10');
        CountrySubentityCodeArray.Add(CountrySubentityCodeObject);
        PostalAddressObject.Add('CountrySubentityCode', CountrySubentityCodeArray);

        // Address Lines
        LineObject.Add('_', 'Lot 66');
        LineArray.Add(LineObject);
        AddressLineObject.Add('Line', LineArray);

        Clear(LineArray);
        LineObject.Add('_', 'Bangunan Merdeka');
        LineArray.Add(LineObject);
        AddressLineObject.Add('Line', LineArray);

        Clear(LineArray);
        LineObject.Add('_', 'Persiaran Jaya');
        LineArray.Add(LineObject);
        AddressLineObject.Add('Line', LineArray);

        PostalAddressObject.Add('AddressLine', AddressLineArray);

        // Country
        IdentificationCodeObject.Add('_', 'MYS');
        IdentificationCodeObject.Add('listID', 'ISO3166-1');
        IdentificationCodeObject.Add('listAgencyID', '6');
        CountryObject.Add('IdentificationCode', IdentificationCodeObject);
        PostalAddressObject.Add('Country', CountryArray);

        PartyObject.Add('PostalAddress', PostalAddressArray);

        // Party Legal Entity
        RegistrationNameObject.Add('_', CompanyInfo.Name);
        RegistrationNameArray.Add(RegistrationNameObject);
        PartyLegalEntityObject.Add('RegistrationName', RegistrationNameArray);
        PartyLegalEntityArray.Add(PartyLegalEntityObject);
        PartyObject.Add('PartyLegalEntity', PartyLegalEntityArray);

        // Contact
        TelephoneObject.Add('_', '+6067671188');
        TelephoneArray.Add(TelephoneObject);
        ContactObject.Add('Telephone', TelephoneArray);

        ElectronicMailObject.Add('_', 'finance@jotexfabrics.com');
        ElectronicMailArray.Add(ElectronicMailObject);
        ContactObject.Add('ElectronicMail', ElectronicMailArray);

        PartyObject.Add('Contact', ContactArray);
    end;

    /// <summary>
    /// Builds the customer party structure following the sample format
    /// </summary>
    local procedure BuildCustomerPartyStructure(var CustomerPartyObject: JsonObject; Customer: Record Customer)
    var
        PartyIdentificationArray: JsonArray;
        PartyIdentificationObject: JsonObject;
        IDObject: JsonObject;
        SchemeIDObject: JsonObject;
        BRNObject: JsonObject;
        ID2Object: JsonObject;
        SchemeID2Object: JsonObject;
        SSTObject: JsonObject;
        ID3Object: JsonObject;
        SchemeID3Object: JsonObject;
        TTXObject: JsonObject;
        ID4Object: JsonObject;
        SchemeID4Object: JsonObject;
        PostalAddressArray: JsonArray;
        PostalAddressObject: JsonObject;
        CityNameArray: JsonArray;
        CityNameObject: JsonObject;
        PostalZoneArray: JsonArray;
        PostalZoneObject: JsonObject;
        CountrySubentityCodeArray: JsonArray;
        CountrySubentityCodeObject: JsonObject;
        AddressLineArray: JsonArray;
        AddressLineObject: JsonObject;
        LineArray: JsonArray;
        LineObject: JsonObject;
        CountryArray: JsonArray;
        CountryObject: JsonObject;
        IdentificationCodeArray: JsonArray;
        IdentificationCodeObject: JsonObject;
        PartyLegalEntityArray: JsonArray;
        PartyLegalEntityObject: JsonObject;
        RegistrationNameArray: JsonArray;
        RegistrationNameObject: JsonObject;
        ContactArray: JsonArray;
        ContactObject: JsonObject;
        TelephoneArray: JsonArray;
        TelephoneObject: JsonObject;
        ElectronicMailArray: JsonArray;
        ElectronicMailObject: JsonObject;
    begin
        // Party Identification - TIN
        IDObject.Add('_', Customer."VAT Registration No.");
        IDObject.Add('schemeID', 'TIN');
        PartyIdentificationObject.Add('ID', IDObject);
        PartyIdentificationArray.Add(PartyIdentificationObject);

        // Party Identification - BRN
        BRNObject.Add('_', '202401002338');
        BRNObject.Add('schemeID', 'BRN');
        PartyIdentificationArray.Add(BRNObject);

        // Party Identification - SST
        SSTObject.Add('_', 'NA');
        SSTObject.Add('schemeID', 'SST');
        PartyIdentificationArray.Add(SSTObject);

        // Party Identification - TTX
        TTXObject.Add('_', 'NA');
        TTXObject.Add('schemeID', 'TTX');
        PartyIdentificationArray.Add(TTXObject);

        CustomerPartyObject.Add('PartyIdentification', PartyIdentificationArray);

        // Postal Address
        CityNameObject.Add('_', 'Kuala Lumpur');
        CityNameArray.Add(CityNameObject);
        PostalAddressObject.Add('CityName', CityNameArray);

        PostalZoneObject.Add('_', '50480');
        PostalZoneArray.Add(PostalZoneObject);
        PostalAddressObject.Add('PostalZone', PostalZoneArray);

        CountrySubentityCodeObject.Add('_', '10');
        CountrySubentityCodeArray.Add(CountrySubentityCodeObject);
        PostalAddressObject.Add('CountrySubentityCode', CountrySubentityCodeArray);

        // Address Lines
        LineObject.Add('_', 'Lot 66');
        LineArray.Add(LineObject);
        AddressLineObject.Add('Line', LineArray);

        Clear(LineArray);
        LineObject.Add('_', 'Bangunan Merdeka');
        LineArray.Add(LineObject);
        AddressLineObject.Add('Line', LineArray);

        Clear(LineArray);
        LineObject.Add('_', 'Persiaran Jaya');
        LineArray.Add(LineObject);
        AddressLineObject.Add('Line', LineArray);

        PostalAddressObject.Add('AddressLine', AddressLineArray);

        // Country
        IdentificationCodeObject.Add('_', 'MYS');
        IdentificationCodeObject.Add('listID', 'ISO3166-1');
        IdentificationCodeObject.Add('listAgencyID', '6');
        CountryObject.Add('IdentificationCode', IdentificationCodeObject);
        PostalAddressObject.Add('Country', CountryArray);

        CustomerPartyObject.Add('PostalAddress', PostalAddressArray);

        // Party Legal Entity
        RegistrationNameObject.Add('_', Customer.Name);
        RegistrationNameArray.Add(RegistrationNameObject);
        PartyLegalEntityObject.Add('RegistrationName', RegistrationNameArray);
        PartyLegalEntityArray.Add(PartyLegalEntityObject);
        CustomerPartyObject.Add('PartyLegalEntity', PartyLegalEntityArray);

        // Contact
        TelephoneObject.Add('_', '+60137605191');
        TelephoneArray.Add(TelephoneObject);
        ContactObject.Add('Telephone', TelephoneArray);

        ElectronicMailObject.Add('_', 'enquiry.ywrcurtainssb@gmail.com');
        ElectronicMailArray.Add(ElectronicMailObject);
        ContactObject.Add('ElectronicMail', ElectronicMailArray);

        CustomerPartyObject.Add('Contact', ContactArray);
    end;

    /// <summary>
    /// Builds the delivery structure following the sample format
    /// </summary>
    local procedure BuildDeliveryStructure(var DeliveryObject: JsonObject; Customer: Record Customer)
    var
        DeliveryPartyArray: JsonArray;
        DeliveryPartyObject: JsonObject;
        DeliveryPartyLegalEntityArray: JsonArray;
        DeliveryPartyLegalEntityObject: JsonObject;
        DeliveryRegistrationNameArray: JsonArray;
        DeliveryRegistrationNameObject: JsonObject;
        DeliveryPostalAddressArray: JsonArray;
        DeliveryPostalAddressObject: JsonObject;
        DeliveryCityNameArray: JsonArray;
        DeliveryCityNameObject: JsonObject;
        DeliveryPostalZoneArray: JsonArray;
        DeliveryPostalZoneObject: JsonObject;
        DeliveryCountrySubentityCodeArray: JsonArray;
        DeliveryCountrySubentityCodeObject: JsonObject;
        DeliveryAddressLineArray: JsonArray;
        DeliveryAddressLineObject: JsonObject;
        DeliveryLineArray: JsonArray;
        DeliveryLineObject: JsonObject;
        DeliveryCountryArray: JsonArray;
        DeliveryCountryObject: JsonObject;
        DeliveryIdentificationCodeArray: JsonArray;
        DeliveryIdentificationCodeObject: JsonObject;
        DeliveryPartyIdentificationArray: JsonArray;
        DeliveryPartyIdentificationObject: JsonObject;
        DeliveryIDObject: JsonObject;
        DeliverySchemeIDObject: JsonObject;
        DeliveryBRNObject: JsonObject;
        DeliveryID2Object: JsonObject;
        DeliverySchemeID2Object: JsonObject;
        ShipmentArray: JsonArray;
        ShipmentObject: JsonObject;
        ShipmentIDArray: JsonArray;
        ShipmentIDObject: JsonObject;
        FreightAllowanceChargeArray: JsonArray;
        FreightAllowanceChargeObject: JsonObject;
        ChargeIndicatorArray: JsonArray;
        ChargeIndicatorObject: JsonObject;
        AllowanceChargeReasonArray: JsonArray;
        AllowanceChargeReasonObject: JsonObject;
        AmountArray: JsonArray;
        AmountObject: JsonObject;
    begin
        // Delivery Party Legal Entity
        DeliveryRegistrationNameObject.Add('_', '');
        DeliveryRegistrationNameArray.Add(DeliveryRegistrationNameObject);
        DeliveryPartyLegalEntityObject.Add('RegistrationName', DeliveryRegistrationNameArray);
        DeliveryPartyLegalEntityArray.Add(DeliveryPartyLegalEntityObject);
        DeliveryPartyObject.Add('PartyLegalEntity', DeliveryPartyLegalEntityArray);

        // Delivery Postal Address
        DeliveryCityNameObject.Add('_', '');
        DeliveryCityNameArray.Add(DeliveryCityNameObject);
        DeliveryPostalAddressObject.Add('CityName', DeliveryCityNameArray);

        DeliveryPostalZoneObject.Add('_', '');
        DeliveryPostalZoneArray.Add(DeliveryPostalZoneObject);
        DeliveryPostalAddressObject.Add('PostalZone', DeliveryPostalZoneArray);

        DeliveryCountrySubentityCodeObject.Add('_', '');
        DeliveryCountrySubentityCodeArray.Add(DeliveryCountrySubentityCodeObject);
        DeliveryPostalAddressObject.Add('CountrySubentityCode', DeliveryCountrySubentityCodeArray);

        // Delivery Address Lines
        DeliveryLineObject.Add('_', '');
        DeliveryLineArray.Add(DeliveryLineObject);
        DeliveryAddressLineObject.Add('Line', DeliveryLineArray);

        Clear(DeliveryLineArray);
        DeliveryLineObject.Add('_', '');
        DeliveryLineArray.Add(DeliveryLineObject);
        DeliveryAddressLineObject.Add('Line', DeliveryLineArray);

        Clear(DeliveryLineArray);
        DeliveryLineObject.Add('_', '');
        DeliveryLineArray.Add(DeliveryLineObject);
        DeliveryAddressLineObject.Add('Line', DeliveryLineArray);

        DeliveryPostalAddressObject.Add('AddressLine', DeliveryAddressLineArray);

        // Delivery Country
        DeliveryIdentificationCodeObject.Add('_', '');
        DeliveryIdentificationCodeObject.Add('listID', 'ISO3166-1');
        DeliveryIdentificationCodeObject.Add('listAgencyID', '6');
        DeliveryCountryObject.Add('IdentificationCode', DeliveryIdentificationCodeObject);
        DeliveryPostalAddressObject.Add('Country', DeliveryCountryArray);

        DeliveryPartyObject.Add('PostalAddress', DeliveryPostalAddressArray);

        // Delivery Party Identification
        DeliveryIDObject.Add('_', '');
        DeliveryIDObject.Add('schemeID', 'TIN');
        DeliveryPartyIdentificationObject.Add('ID', DeliveryIDObject);
        DeliveryPartyIdentificationArray.Add(DeliveryPartyIdentificationObject);

        DeliveryBRNObject.Add('_', '');
        DeliveryBRNObject.Add('schemeID', 'BRN');
        DeliveryPartyIdentificationArray.Add(DeliveryBRNObject);

        DeliveryPartyObject.Add('PartyIdentification', DeliveryPartyIdentificationArray);

        DeliveryObject.Add('DeliveryParty', DeliveryPartyArray);

        // Shipment
        ShipmentIDObject.Add('_', '');
        ShipmentIDArray.Add(ShipmentIDObject);
        ShipmentObject.Add('ID', ShipmentIDArray);

        // Freight Allowance Charge
        ChargeIndicatorObject.Add('_', true);
        ChargeIndicatorArray.Add(ChargeIndicatorObject);
        FreightAllowanceChargeObject.Add('ChargeIndicator', ChargeIndicatorArray);

        AllowanceChargeReasonObject.Add('_', '');
        AllowanceChargeReasonArray.Add(AllowanceChargeReasonObject);
        FreightAllowanceChargeObject.Add('AllowanceChargeReason', AllowanceChargeReasonArray);

        AmountObject.Add('_', 0.0);
        AmountObject.Add('currencyID', 'MYR');
        AmountArray.Add(AmountObject);
        FreightAllowanceChargeObject.Add('Amount', AmountArray);

        ShipmentObject.Add('FreightAllowanceCharge', FreightAllowanceChargeArray);
        DeliveryObject.Add('Shipment', ShipmentArray);
    end;

    /// <summary>
    /// Builds the allowance charge structure following the sample format
    /// </summary>
    local procedure BuildAllowanceChargeStructure(var AllowanceChargeArray: JsonArray)
    var
        AllowanceChargeObject: JsonObject;
        ChargeIndicatorArray: JsonArray;
        ChargeIndicatorObject: JsonObject;
        AllowanceChargeReasonArray: JsonArray;
        AllowanceChargeReasonObject: JsonObject;
        AmountArray: JsonArray;
        AmountObject: JsonObject;
        AllowanceChargeObject2: JsonObject;
        ChargeIndicator2Array: JsonArray;
        ChargeIndicator2Object: JsonObject;
        AllowanceChargeReason2Array: JsonArray;
        AllowanceChargeReason2Object: JsonObject;
        Amount2Array: JsonArray;
        Amount2Object: JsonObject;
    begin
        // First allowance charge (allowance)
        ChargeIndicatorObject.Add('_', false);
        ChargeIndicatorArray.Add(ChargeIndicatorObject);
        AllowanceChargeObject.Add('ChargeIndicator', ChargeIndicatorArray);

        AllowanceChargeReasonObject.Add('_', 'Sample Description');
        AllowanceChargeReasonArray.Add(AllowanceChargeReasonObject);
        AllowanceChargeObject.Add('AllowanceChargeReason', AllowanceChargeReasonArray);

        AmountObject.Add('_', 100.0);
        AmountObject.Add('currencyID', 'MYR');
        AmountArray.Add(AmountObject);
        AllowanceChargeObject.Add('Amount', AmountArray);

        AllowanceChargeArray.Add(AllowanceChargeObject);

        // Second allowance charge (charge)
        ChargeIndicator2Object.Add('_', true);
        ChargeIndicator2Array.Add(ChargeIndicator2Object);
        AllowanceChargeObject2.Add('ChargeIndicator', ChargeIndicator2Array);

        AllowanceChargeReason2Object.Add('_', 'Service charge');
        AllowanceChargeReason2Array.Add(AllowanceChargeReason2Object);
        AllowanceChargeObject2.Add('AllowanceChargeReason', AllowanceChargeReason2Array);

        Amount2Object.Add('_', 100.0);
        Amount2Object.Add('currencyID', 'MYR');
        Amount2Array.Add(Amount2Object);
        AllowanceChargeObject2.Add('Amount', Amount2Array);

        AllowanceChargeArray.Add(AllowanceChargeObject2);
    end;

    /// <summary>
    /// Builds the tax total structure following the sample format
    /// </summary>
    local procedure BuildTaxTotalStructure(var TaxTotalObject: JsonObject; TotalAmount: Decimal; TotalTaxAmount: Decimal)
    var
        TaxAmountArray: JsonArray;
        TaxAmountObject: JsonObject;
        TaxSubtotalArray: JsonArray;
        TaxSubtotalObject: JsonObject;
        TaxableAmountArray: JsonArray;
        TaxableAmountObject: JsonObject;
        TaxAmount2Array: JsonArray;
        TaxAmount2Object: JsonObject;
        TaxCategoryArray: JsonArray;
        TaxCategoryObject: JsonObject;
        TaxCategoryIDArray: JsonArray;
        TaxCategoryIDObject: JsonObject;
        TaxSchemeArray: JsonArray;
        TaxSchemeObject: JsonObject;
        TaxSchemeIDArray: JsonArray;
        TaxSchemeIDObject: JsonObject;
    begin
        // Tax Amount
        TaxAmountObject.Add('_', Format(TotalTaxAmount));
        TaxAmountObject.Add('currencyID', 'MYR');
        TaxAmountArray.Add(TaxAmountObject);
        TaxTotalObject.Add('TaxAmount', TaxAmountArray);

        // Tax Subtotal
        TaxableAmountObject.Add('_', Format(TotalAmount));
        TaxableAmountObject.Add('currencyID', 'MYR');
        TaxSubtotalObject.Add('TaxableAmount', TaxableAmountArray);

        TaxAmount2Object.Add('_', Format(TotalTaxAmount));
        TaxAmount2Object.Add('currencyID', 'MYR');
        TaxSubtotalObject.Add('TaxAmount', TaxAmount2Array);

        // Tax Category
        TaxCategoryIDObject.Add('_', '01');
        TaxCategoryIDArray.Add(TaxCategoryIDObject);
        TaxCategoryObject.Add('ID', TaxCategoryIDArray);

        // Tax Scheme
        TaxSchemeIDObject.Add('_', 'OTH');
        TaxSchemeIDObject.Add('schemeID', 'UN/ECE 5153');
        TaxSchemeIDObject.Add('schemeAgencyID', '6');
        TaxSchemeObject.Add('ID', TaxSchemeIDArray);

        TaxCategoryObject.Add('TaxScheme', TaxSchemeArray);
        TaxSubtotalObject.Add('TaxCategory', TaxCategoryArray);

        TaxTotalObject.Add('TaxSubtotal', TaxSubtotalArray);
    end;

    /// <summary>
    /// Builds the legal monetary total structure following the sample format
    /// </summary>
    local procedure BuildLegalMonetaryTotalStructure(var LegalMonetaryTotalObject: JsonObject; TotalAmount: Decimal; TotalTaxAmount: Decimal)
    var
        LineExtensionAmountArray: JsonArray;
        LineExtensionAmountObject: JsonObject;
        TaxExclusiveAmountArray: JsonArray;
        TaxExclusiveAmountObject: JsonObject;
        TaxInclusiveAmountArray: JsonArray;
        TaxInclusiveAmountObject: JsonObject;
        AllowanceTotalAmountArray: JsonArray;
        AllowanceTotalAmountObject: JsonObject;
        ChargeTotalAmountArray: JsonArray;
        ChargeTotalAmountObject: JsonObject;
        PayableRoundingAmountArray: JsonArray;
        PayableRoundingAmountObject: JsonObject;
        PayableAmountArray: JsonArray;
        PayableAmountObject: JsonObject;
    begin
        // Line Extension Amount
        LineExtensionAmountObject.Add('_', Format(TotalAmount));
        LineExtensionAmountObject.Add('currencyID', 'MYR');
        LineExtensionAmountArray.Add(LineExtensionAmountObject);
        LegalMonetaryTotalObject.Add('LineExtensionAmount', LineExtensionAmountArray);

        // Tax Exclusive Amount
        TaxExclusiveAmountObject.Add('_', Format(TotalAmount));
        TaxExclusiveAmountObject.Add('currencyID', 'MYR');
        TaxExclusiveAmountArray.Add(TaxExclusiveAmountObject);
        LegalMonetaryTotalObject.Add('TaxExclusiveAmount', TaxExclusiveAmountArray);

        // Tax Inclusive Amount
        TaxInclusiveAmountObject.Add('_', Format(TotalAmount + TotalTaxAmount));
        TaxInclusiveAmountObject.Add('currencyID', 'MYR');
        TaxInclusiveAmountArray.Add(TaxInclusiveAmountObject);
        LegalMonetaryTotalObject.Add('TaxInclusiveAmount', TaxInclusiveAmountArray);

        // Allowance Total Amount
        AllowanceTotalAmountObject.Add('_', Format(TotalAmount));
        AllowanceTotalAmountObject.Add('currencyID', 'MYR');
        AllowanceTotalAmountArray.Add(AllowanceTotalAmountObject);
        LegalMonetaryTotalObject.Add('AllowanceTotalAmount', AllowanceTotalAmountArray);

        // Charge Total Amount
        ChargeTotalAmountObject.Add('_', Format(TotalAmount));
        ChargeTotalAmountObject.Add('currencyID', 'MYR');
        ChargeTotalAmountArray.Add(ChargeTotalAmountObject);
        LegalMonetaryTotalObject.Add('ChargeTotalAmount', ChargeTotalAmountArray);

        // Payable Rounding Amount
        PayableRoundingAmountObject.Add('_', 0.3);
        PayableRoundingAmountObject.Add('currencyID', 'MYR');
        PayableRoundingAmountArray.Add(PayableRoundingAmountObject);
        LegalMonetaryTotalObject.Add('PayableRoundingAmount', PayableRoundingAmountArray);

        // Payable Amount
        PayableAmountObject.Add('_', Format(TotalAmount + TotalTaxAmount));
        PayableAmountObject.Add('currencyID', 'MYR');
        PayableAmountArray.Add(PayableAmountObject);
        LegalMonetaryTotalObject.Add('PayableAmount', PayableAmountArray);
    end;

    /// <summary>
    /// Calculate credit memo totals from lines
    /// </summary>
    /// <param name="SalesCrMemoHeader">The credit memo header</param>
    /// <param name="TotalAmount">Output: Total line amount</param>
    /// <param name="TotalTaxAmount">Output: Total tax amount</param>
    local procedure CalculateCreditMemoTotals(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; var TotalAmount: Decimal; var TotalTaxAmount: Decimal)
    var
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
        LineAmount: Decimal;
        LineTaxAmount: Decimal;
    begin
        TotalAmount := 0;
        TotalTaxAmount := 0;

        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        if SalesCrMemoLine.FindSet() then
            repeat
                LineAmount := SalesCrMemoLine."Line Amount";
                LineTaxAmount := SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine."Line Amount";
                TotalAmount += LineAmount;
                TotalTaxAmount += LineTaxAmount;
            until SalesCrMemoLine.Next() = 0;
    end;

    // ======================================================================================================
    // CREDIT NOTE UBL JSON BUILDING PROCEDURES
    // ======================================================================================================

    /// <summary>
    /// Main procedure to build complete credit note UBL JSON
    /// </summary>
    /// <param name="SalesCrMemoHeader">The credit memo header to build JSON for</param>
    /// <returns>Complete UBL JSON string for credit note</returns>
    procedure BuildCreditMemoUBLJson(SalesCrMemoHeader: Record "Sales Cr.Memo Header"): Text
    var
        UBLDocument: JsonObject;
        JsonText: Text;
    begin
        // Build the complete credit note UBL document
        UBLDocument := BuildEnhancedCreditMemoDocument(SalesCrMemoHeader);

        // Convert to JSON text
        UBLDocument.WriteTo(JsonText);

        exit(JsonText);
    end;

    // ADDED: Credit memo identification using Invoice structure (LHDN requirement)
    local procedure BuildCreditMemoIdentificationAsInvoice(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        UBLVersionID: JsonObject;
        CustomizationID: JsonObject;
        ProfileID: JsonObject;
        ID: JsonObject;
        IssueDate: JsonObject;
        IssueTime: JsonObject;
        InvoiceTypeCode: JsonObject;
        DocumentCurrencyCode: JsonObject;
        InvoiceTypeCodeAttributes: JsonObject;
    begin
        // Get Invoice object from UBL structure
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // UBL Version (required by myinvois)
        UBLVersionID.Add('_text', '2.1');
        InvoiceObject.Add('cbc:UBLVersionID', UBLVersionID);

        // Customization ID (Malaysia e-Invoice specific)
        CustomizationID.Add('_text', 'MY:1.0');
        InvoiceObject.Add('cbc:CustomizationID', CustomizationID);

        // Profile ID (Malaysia e-Invoice profile)
        ProfileID.Add('_text', 'reporting:1.0');
        InvoiceObject.Add('cbc:ProfileID', ProfileID);

        // Credit Memo Number
        ID.Add('_text', SalesCrMemoHeader."No.");
        InvoiceObject.Add('cbc:ID', ID);

        // FORCE: Always use yesterday's date to ensure it's never in the future
        IssueDate.Add('_text', Format(CalcDate('-1D', Today()), 0, '<Year4>-<Month,2>-<Day,2>'));
        InvoiceObject.Add('cbc:IssueDate', IssueDate);

        IssueTime.Add('_text', Format(DT2Time(CurrentDateTime - 300000), 0, '<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        InvoiceObject.Add('cbc:IssueTime', IssueTime);

        // CRITICAL: Correct InvoiceTypeCode for credit notes
        InvoiceTypeCode.Add('_text', '02'); // Credit Note
        InvoiceTypeCodeAttributes.Add('listVersionID', '1.1'); // LHDN v1.1 requirement
        InvoiceTypeCode.Add('_attributes', InvoiceTypeCodeAttributes);
        InvoiceObject.Add('cbc:InvoiceTypeCode', InvoiceTypeCode);

        // Document Currency Code
        DocumentCurrencyCode.Add('_text', GetDocumentCurrencyCode(SalesCrMemoHeader));
        InvoiceObject.Add('cbc:DocumentCurrencyCode', DocumentCurrencyCode);

        // ADDED: Tax Currency Code (required by LHDN)
        InvoiceObject.Add('cbc:TaxCurrencyCode', DocumentCurrencyCode);

        // Update the document
        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    // ADDED: Credit memo billing reference using Invoice structure
    local procedure BuildCreditMemoBillingReferenceAsInvoice(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        BillingReferenceArray: JsonArray;
        BillingReferenceObject: JsonObject;
        InvoiceDocumentReferenceArray: JsonArray;
        InvoiceDocumentReferenceObject: JsonObject;
        IDObject: JsonObject;
        UUIDObject: JsonObject;
        eInvoiceSubmissionLog: Record "eInvoice Submission Log";
        OriginalInvoiceUUID: Text;
    begin
        if SalesCrMemoHeader."Applies-to Doc. No." = '' then
            exit;

        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Try to find the original invoice UUID from submission log
        eInvoiceSubmissionLog.SetRange("Invoice No.", SalesCrMemoHeader."Applies-to Doc. No.");
        eInvoiceSubmissionLog.SetRange(Status, 'Valid');
        if eInvoiceSubmissionLog.FindLast() then
            OriginalInvoiceUUID := eInvoiceSubmissionLog."Document UUID"
        else
            OriginalInvoiceUUID := 'Reference Invoice UUID'; // Fallback

        // Reference to original invoice
        IDObject.Add('_', SalesCrMemoHeader."Applies-to Doc. No.");
        InvoiceDocumentReferenceObject.Add('ID', IDObject);

        // Add UUID if available from submission log
        UUIDObject.Add('_', OriginalInvoiceUUID);
        InvoiceDocumentReferenceObject.Add('UUID', UUIDObject);

        InvoiceDocumentReferenceArray.Add(InvoiceDocumentReferenceObject);
        BillingReferenceObject.Add('InvoiceDocumentReference', InvoiceDocumentReferenceArray);
        BillingReferenceArray.Add(BillingReferenceObject);

        InvoiceObject.Add('BillingReference', BillingReferenceArray);
        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    // ADDED: Credit memo lines using Invoice structure
    local procedure BuildCreditMemoLinesAsInvoice(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        InvoiceLinesArray: JsonArray;
        SalesCrMemoLine: Record "Sales Cr.Memo Line";
    begin
        // Get Invoice object from UBL structure
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Build invoice lines array (for credit memo)
        SalesCrMemoLine.SetRange("Document No.", SalesCrMemoHeader."No.");
        if SalesCrMemoLine.FindSet() then
            repeat
                BuildSingleCreditMemoLineAsInvoice(InvoiceLinesArray, SalesCrMemoLine);
            until SalesCrMemoLine.Next() = 0;

        // Add invoice lines to document
        InvoiceObject.Add('cac:InvoiceLine', InvoiceLinesArray);

        // Update the document
        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    // ADDED: Single credit memo line using Invoice structure
    local procedure BuildSingleCreditMemoLineAsInvoice(var InvoiceLinesArray: JsonArray; SalesCrMemoLine: Record "Sales Cr.Memo Line")
    var
        InvoiceLineObject: JsonObject;
        ID: JsonObject;
        InvoicedQuantity: JsonObject;
        LineExtensionAmount: JsonObject;
        TaxTotal: JsonObject;
        TaxSubtotal: JsonObject;
        TaxCategory: JsonObject;
        TaxScheme: JsonObject;
        Item: JsonObject;
        ItemDescription: JsonObject;
        Name: JsonObject;
        SellersItemIdentification: JsonObject;
        ID2: JsonObject;
        Price: JsonObject;
        PriceAmount: JsonObject;
        TaxAmount: Decimal;
        LineTaxAmount: JsonObject;
        LineTaxableAmount: JsonObject;
        LineTaxSubtotalAmount: JsonObject;
    begin
        // CORRECTED: Use positive amounts for credit notes
        TaxAmount := SalesCrMemoLine."Amount Including VAT" - SalesCrMemoLine."Line Amount";

        // Invoice Line ID
        ID.Add('_text', Format(SalesCrMemoLine."Line No."));
        InvoiceLineObject.Add('cbc:ID', ID);

        // CORRECTED: Use positive quantity for credit memo (LHDN expects positive values)
        InvoicedQuantity.Add('_text', Format(SalesCrMemoLine.Quantity));
        InvoicedQuantity.Add('unitCode', 'C62');
        InvoiceLineObject.Add('cbc:InvoicedQuantity', InvoicedQuantity);

        // CORRECTED: Use positive line amount
        LineExtensionAmount.Add('_text', Format(SalesCrMemoLine."Line Amount"));
        LineExtensionAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        InvoiceLineObject.Add('cbc:LineExtensionAmount', LineExtensionAmount);

        // Add Tax Total for this line
        LineTaxAmount.Add('_text', Format(TaxAmount));
        LineTaxAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        TaxTotal.Add('cbc:TaxAmount', LineTaxAmount);

        // Tax Subtotal
        LineTaxableAmount.Add('_text', Format(SalesCrMemoLine."Line Amount"));
        LineTaxableAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        TaxSubtotal.Add('cbc:TaxableAmount', LineTaxableAmount);

        LineTaxSubtotalAmount.Add('_text', Format(TaxAmount));
        LineTaxSubtotalAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        TaxSubtotal.Add('cbc:TaxAmount', LineTaxSubtotalAmount);

        // Tax Category
        TaxCategory.Add('cbc:ID', 'S'); // Standard rate
        TaxCategory.Add('cbc:Percent', Format(SalesCrMemoLine."VAT %"));

        // ADDED: Tax Exemption Reason (required by LHDN)
        TaxCategory.Add('cbc:TaxExemptionReason', BuildTaxExemptionReason());

        // Tax Scheme
        TaxScheme.Add('cbc:ID', 'OTH');
        TaxScheme.Add('schemeID', 'UN/ECE 5153');
        TaxScheme.Add('schemeAgencyID', '6'); // ADDED: Scheme Agency ID (required by LHDN)
        TaxCategory.Add('cac:TaxScheme', TaxScheme);
        TaxSubtotal.Add('cac:TaxCategory', TaxCategory);

        TaxTotal.Add('cac:TaxSubtotal', TaxSubtotal);
        InvoiceLineObject.Add('cac:TaxTotal', TaxTotal);

        // Item Information
        Item.Add('cbc:Description', SalesCrMemoLine.Description);

        // ADDED: Commodity Classification (required by LHDN)
        Item.Add('cac:CommodityClassification', BuildCommodityClassification());

        // Item Name
        Name.Add('_text', SalesCrMemoLine.Description);
        ItemDescription.Add('cbc:Name', Name);
        Item.Add('cac:Description', ItemDescription);

        // Item ID
        ID2.Add('_text', SalesCrMemoLine."No.");
        SellersItemIdentification.Add('cbc:ID', ID2);
        Item.Add('cac:SellersItemIdentification', SellersItemIdentification);

        // ADDED: Origin Country (required by LHDN)
        Item.Add('cac:OriginCountry', BuildOriginCountry());

        // Price Information
        PriceAmount.Add('_text', Format(SalesCrMemoLine."Unit Price"));
        PriceAmount.Add('currencyID', GetDocumentCurrencyCode(SalesCrMemoLine));
        Price.Add('cbc:PriceAmount', PriceAmount);

        // ADDED: Item Price Extension (required by LHDN)
        InvoiceLineObject.Add('cac:ItemPriceExtension', BuildItemPriceExtension(SalesCrMemoLine));

        // ADDED: Allowance Charge (required by LHDN)
        InvoiceLineObject.Add('cac:AllowanceCharge', BuildAllowanceCharge(SalesCrMemoLine));

        // Add item and price to line
        InvoiceLineObject.Add('cac:Item', Item);
        InvoiceLineObject.Add('cac:Price', Price);

        // Add line to array
        InvoiceLinesArray.Add(InvoiceLineObject);
    end;

    // ADDED: Supplier party using Invoice structure
    local procedure BuildSupplierPartyAsInvoice(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        AccountingSupplierParty: JsonObject;
        PartyObject: JsonObject;
        PartyIdentification: JsonObject;
        PartyName: JsonObject;
        CompanyInfo: Record "Company Information";
    begin
        CompanyInfo.Get();
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Build supplier party structure with basic information
        BuildPartyIdentification(PartyIdentification, CompanyInfo."Registration No.");
        PartyObject.Add('cac:PartyIdentification', PartyIdentification);

        BuildPartyName(PartyName, CompanyInfo.Name);
        PartyObject.Add('cac:PartyName', PartyName);

        AccountingSupplierParty.Add('cac:Party', PartyObject);
        InvoiceObject.Add('cac:AccountingSupplierParty', AccountingSupplierParty);

        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    // ADDED: Customer party using Invoice structure
    local procedure BuildCustomerPartyAsInvoice(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        AccountingCustomerParty: JsonObject;
        PartyObject: JsonObject;
        PartyIdentification: JsonObject;
        PartyName: JsonObject;
        Customer: Record Customer;
        CustomerTIN: Text;
    begin
        Customer.Get(SalesCrMemoHeader."Sell-to Customer No.");
        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Use VAT Registration No. as TIN placeholder
        CustomerTIN := Customer."VAT Registration No.";
        if CustomerTIN = '' then
            CustomerTIN := Customer."No."; // Fallback to customer number

        // Build customer party structure with basic information
        BuildPartyIdentification(PartyIdentification, CustomerTIN);
        PartyObject.Add('cac:PartyIdentification', PartyIdentification);

        BuildPartyName(PartyName, SalesCrMemoHeader."Sell-to Customer Name");
        PartyObject.Add('cac:PartyName', PartyName);

        AccountingCustomerParty.Add('cac:Party', PartyObject);
        InvoiceObject.Add('cac:AccountingCustomerParty', AccountingCustomerParty);

        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    // ADDED: Document-level legal monetary total using Invoice structure
    local procedure BuildDocumentLevelLegalMonetaryTotalAsInvoice(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        LegalMonetaryTotal: JsonObject;
        LineExtensionAmount: JsonObject;
        TaxExclusiveAmount: JsonObject;
        TaxInclusiveAmount: JsonObject;
        PayableAmount: JsonObject;
        CurrencyCode: Text;
        TotalAmount: Decimal;
        TotalTaxAmount: Decimal;
    begin
        CurrencyCode := GetDocumentCurrencyCode(SalesCrMemoHeader);
        TotalAmount := SalesCrMemoHeader."Amount";
        TotalTaxAmount := SalesCrMemoHeader."Amount Including VAT" - SalesCrMemoHeader."Amount";

        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Line Extension Amount
        LineExtensionAmount.Add('_text', Format(TotalAmount));
        LineExtensionAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:LineExtensionAmount', LineExtensionAmount);

        // Tax Exclusive Amount
        TaxExclusiveAmount.Add('_text', Format(TotalAmount));
        TaxExclusiveAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:TaxExclusiveAmount', TaxExclusiveAmount);

        // Tax Inclusive Amount
        TaxInclusiveAmount.Add('_text', Format(TotalAmount + TotalTaxAmount));
        TaxInclusiveAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:TaxInclusiveAmount', TaxInclusiveAmount);

        // Payable Amount
        PayableAmount.Add('_text', Format(TotalAmount + TotalTaxAmount));
        PayableAmount.Add('currencyID', CurrencyCode);
        LegalMonetaryTotal.Add('cbc:PayableAmount', PayableAmount);

        InvoiceObject.Add('cac:LegalMonetaryTotal', LegalMonetaryTotal);
        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    // ADDED: Document-level tax total using Invoice structure
    local procedure BuildDocumentLevelTaxTotalAsInvoice(var UBLDocument: JsonObject; SalesCrMemoHeader: Record "Sales Cr.Memo Header")
    var
        InvoiceToken: JsonToken;
        InvoiceObject: JsonObject;
        TaxTotal: JsonObject;
        TaxSubtotal: JsonObject;
        TaxCategory: JsonObject;
        TaxScheme: JsonObject;
        TaxAmount: JsonObject;
        TaxableAmount: JsonObject;
        CurrencyCode: Text;
        TotalTaxAmount: Decimal;
    begin
        CurrencyCode := GetDocumentCurrencyCode(SalesCrMemoHeader);
        TotalTaxAmount := SalesCrMemoHeader."Amount Including VAT" - SalesCrMemoHeader."Amount";

        UBLDocument.Get('Invoice', InvoiceToken);
        InvoiceObject := InvoiceToken.AsObject();

        // Document-level Tax Total
        TaxAmount.Add('_text', Format(TotalTaxAmount));
        TaxAmount.Add('currencyID', CurrencyCode);
        TaxTotal.Add('cbc:TaxAmount', TaxAmount);

        // Tax Subtotal
        TaxableAmount.Add('_text', Format(SalesCrMemoHeader."Amount"));
        TaxableAmount.Add('currencyID', CurrencyCode);
        TaxSubtotal.Add('cbc:TaxableAmount', TaxableAmount);

        // Tax Category
        TaxCategory.Add('cbc:ID', 'S'); // Standard rate
        TaxCategory.Add('cbc:Percent', '10'); // Default VAT rate

        // Tax Scheme
        TaxScheme.Add('cbc:ID', 'OTH');
        TaxScheme.Add('schemeID', 'UN/ECE 5153');
        TaxScheme.Add('schemeAgencyID', '6'); // ADDED: Scheme Agency ID (required by LHDN)
        TaxCategory.Add('cac:TaxScheme', TaxScheme);
        TaxSubtotal.Add('cac:TaxCategory', TaxCategory);

        TaxTotal.Add('cac:TaxSubtotal', TaxSubtotal);
        InvoiceObject.Add('cac:TaxTotal', TaxTotal);
        UBLDocument.Replace('Invoice', InvoiceObject);
    end;

    // UPDATE: Add document type parameter for credit memos
    local procedure BuildAzureFunctionPayload(JsonText: Text; CorrelationId: Text; DocumentType: Text): Text
    var
        RequestJson: JsonObject;
        RequestText: Text;
        eInvoiceSetup: Record "eInvoiceSetup";
        Environment: Text;
    begin
        // Get environment setting
        if eInvoiceSetup.Get() then begin
            case eInvoiceSetup.Environment of
                eInvoiceSetup.Environment::Preprod:
                    Environment := 'PREPROD';
                eInvoiceSetup.Environment::Production:
                    Environment := 'PRODUCTION';
                else
                    Environment := 'PREPROD'; // Default fallback
            end;
        end else
            Environment := 'PREPROD';

        RequestJson.Add('unsignedJson', JsonText);
        RequestJson.Add('invoiceType', '01'); // Keep for compatibility
        RequestJson.Add('documentType', DocumentType); // ADD THIS
        RequestJson.Add('environment', Environment);
        RequestJson.Add('timestamp', Format(CurrentDateTime, 0, '<Year4>-<Month,2>-<Day,2>T<Hours24,2>:<Minutes,2>:<Seconds,2>Z'));
        RequestJson.Add('requestId', CorrelationId);
        RequestJson.WriteTo(RequestText);
        exit(RequestText);
    end;

    // ADD: Credit memo specific procedure
    procedure PostCreditMemoToAzureFunction(SalesCrMemoHeader: Record "Sales Cr.Memo Header"; AzureFunctionUrl: Text; var ResponseText: Text)
    var
        eInvoiceJSONGenerator: Codeunit 50302;
    begin
        // FIXED: Use the JSON Generator's credit memo method which already uses correct Invoice structure
        eInvoiceJSONGenerator.PostCreditMemoToAzureFunction(SalesCrMemoHeader, AzureFunctionUrl, ResponseText);
    end;
}
