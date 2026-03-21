tableextension 50301 eInvSalesInvoiceExt extends "Sales Invoice Header"
{
    fields
    {
        field(50300; "eInvoice UUID"; Text[100])
        {
            Caption = 'KMAX e-Invoice UUID';
            DataClassification = CustomerContent;
        }
        field(50301; "eInvoice QR URL"; Text[250])
        {
            Caption = 'KMAX e-Invoice QR URL';
            DataClassification = CustomerContent;
        }
        field(50302; "eInvoice PDF URL"; Text[250])
        {
            Caption = 'e-Invoice PDF URL';
            DataClassification = CustomerContent;
        }
        field(50304; "eInvoice Submission UID"; Text[100])
        {
            Caption = 'e-Invoice Submission UID';
            DataClassification = CustomerContent;
        }
        field(50305; "eInvoice QR Image"; Media)
        {
            Caption = 'KMAX e-Invoice QR Image';
            DataClassification = CustomerContent;
        }
        field(50306; "eInvoice Document Type"; Code[2])
        {
            Caption = 'e-Invoice Document Type';
            TableRelation = eInvoiceTypes.Code;
            DataClassification = ToBeClassified;
        }
        field(50307; "eInvoice Payment Mode"; Code[20])
        {
            Caption = 'e-Invoice Payment Mode';
            TableRelation = "Payment Modes".Code;
            DataClassification = ToBeClassified;
        }
        field(50308; "eInvoice Currency Code"; Code[20])
        {
            Caption = 'e-Invoice Currency Code';
            TableRelation = "Currency Codes".Code;
            DataClassification = ToBeClassified;
        }
        field(50309; "eInvoice Version Code"; Code[20])
        {
            Caption = 'e-Invoice Version Code';
            TableRelation = "eInvoice Version".Code;
            DataClassification = ToBeClassified;
        }
        field(50310; "eInvoice Validation Status"; Text[50])
        {
            Caption = 'KMAX e-Invoice Validation Status';
            DataClassification = ToBeClassified;
        }
        field(50320; "Latest Submission Status"; Text[50])
        {
            Caption = 'Latest Submission Status';
            FieldClass = FlowField;
            CalcFormula = Lookup("eInvoice Submission Log".Status
                          WHERE("Invoice No." = FIELD("No.")));
            Editable = false;
        }

        field(50321; "Latest Submission Date"; DateTime)
        {
            Caption = 'Latest Submission Date';
            FieldClass = FlowField;
            CalcFormula = Lookup("eInvoice Submission Log"."Submission Date"
                          WHERE("Invoice No." = FIELD("No.")));
            Editable = false;
        }

        field(50322; "Latest LHDN UUID"; Text[100])
        {
            Caption = 'Latest e-Invoice UUID';
            FieldClass = FlowField;
            CalcFormula = Lookup("eInvoice Submission Log"."Document UUID"
                          WHERE("Invoice No." = FIELD("No.")));
            Editable = false;
        }

        field(50323; "Latest Error Message"; Text[2048])
        {
            Caption = 'Latest Error Message';
            FieldClass = FlowField;
            CalcFormula = Lookup("eInvoice Submission Log"."Error Message"
                          WHERE("Invoice No." = FIELD("No.")));
            Editable = false;
        }
    }
}
