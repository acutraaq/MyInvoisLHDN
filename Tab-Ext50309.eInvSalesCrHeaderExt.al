tableextension 50309 eInvSalesCrHeaderExt extends "Sales Cr.Memo Header"
{
    fields
    {
        field(50306; "eInvoice Document Type"; Code[20])
        {
            Caption = 'e-Invoice Document Type';
            TableRelation = eInvoiceTypes.Code;
            DataClassification = ToBeClassified;
        }
        field(50301; "eInvoice Payment Mode"; Code[20])
        {
            Caption = 'e-Invoice Payment Mode';
            TableRelation = "Payment Modes".Code;
            DataClassification = ToBeClassified;
        }
        field(50302; "eInvoice Currency Code"; Code[20])
        {
            Caption = 'e-Invoice Currency Code';
            TableRelation = "Currency Codes".Code;
            DataClassification = ToBeClassified;
        }
        field(50303; "eInvoice Version Code"; Code[20])
        {
            Caption = 'e-Invoice Version Code';
            TableRelation = "eInvoice Version".Code;
            DataClassification = ToBeClassified;
            InitValue = '1.1';  // Default value
        }
        field(50304; "eInvoice UUID"; Text[100])
        {
            Caption = 'KMAX e-Invoice UUID';
            DataClassification = CustomerContent;
        }
        field(50305; "eInvoice Submission UID"; Text[100])
        {
            Caption = 'e-Invoice Submission UID';
            DataClassification = CustomerContent;
        }
        field(50310; "eInvoice Validation Status"; Text[50])
        {
            Caption = 'KMAX e-Invoice Validation Status';
            DataClassification = ToBeClassified;
        }
        field(50311; "eInvoice QR URL"; Text[250])
        {
            Caption = 'KMAX e-Invoice QR URL';
            DataClassification = CustomerContent;
        }
        field(50312; "eInvoice QR Image"; Media)
        {
            Caption = 'KMAX e-Invoice QR Image';
            DataClassification = CustomerContent;
        }
        // CHANGED: Now finds the latest SUBMISSION DATE instead of latest Entry No.
        field(50319; "Latest Submission Date"; DateTime)
        {
            Caption = 'Latest Submission Date';
            FieldClass = FlowField;
            CalcFormula = Max("eInvoice Submission Log"."Submission Date"
                        WHERE("Invoice No." = FIELD("No.")));
            Editable = false;
        }
        // CHANGED: Now looks up Status based on the latest Submission Date
        field(50320; "Latest Submission Status"; Text[50])
        {
            Caption = 'Latest Submission Status';
            FieldClass = FlowField;
            CalcFormula = Lookup("eInvoice Submission Log".Status
                        WHERE("Invoice No." = FIELD("No."),
                        "Submission Date" = FIELD("Latest Submission Date")));
            Editable = false;
        }
        field(50321; "Latest LHDN UUID"; Text[100])
        {
            Caption = 'Latest e-Invoice UUID';
            FieldClass = FlowField;
            CalcFormula = Lookup("eInvoice Submission Log"."Document UUID"
                        WHERE("Invoice No." = FIELD("No."),
                        "Submission Date" = FIELD("Latest Submission Date")));
            Editable = false;
        }

        field(50322; "Latest Error Message"; Text[2048])
        {
            Caption = 'Latest Error Message';
            FieldClass = FlowField;
            CalcFormula = Lookup("eInvoice Submission Log"."Error Message"
                        WHERE("Invoice No." = FIELD("No."),
                        "Submission Date" = FIELD("Latest Submission Date")));
            Editable = false;
        }
    }
    trigger OnInsert()
    begin
        if "eInvoice Version Code" = '' then
            "eInvoice Version Code" := '1.1';

        // Credit memo documents must carry e-Invoice type '02'
        if "eInvoice Document Type" = '' then
            "eInvoice Document Type" := '02';
    end;
}
