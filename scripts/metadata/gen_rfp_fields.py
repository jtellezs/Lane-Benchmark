#!/usr/bin/env python3
"""Writes the RFP_Project__c / RFP_Lane__c / Benchmark_Rate__c field metadata (phase 3a)."""
import os

ROOT = "force-app/main/default/objects"

def w(obj, name, body):
    d = os.path.join(ROOT, obj, "fields")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f"{name}.field-meta.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8" ?>\n'
                '<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n'
                f"    <fullName>{name}</fullName>\n{body}</CustomField>\n")

def text(obj, name, label, length, help=None, required=False):
    h = f"    <inlineHelpText>{help}</inlineHelpText>\n" if help else ""
    w(obj, name, f"    <label>{label}</label>\n    <type>Text</type>\n    <length>{length}</length>\n"
                 f"    <required>{'true' if required else 'false'}</required>\n{h}")

def longtext(obj, name, label, length=32768, lines=5):
    w(obj, name, f"    <label>{label}</label>\n    <type>LongTextArea</type>\n    <length>{length}</length>\n"
                 f"    <visibleLines>{lines}</visibleLines>\n")

def number(obj, name, label, precision, scale):
    w(obj, name, f"    <label>{label}</label>\n    <type>Number</type>\n    <precision>{precision}</precision>\n"
                 f"    <scale>{scale}</scale>\n    <required>false</required>\n    <unique>false</unique>\n")

def currency(obj, name, label, required=False):
    w(obj, name, f"    <label>{label}</label>\n    <type>Currency</type>\n    <precision>16</precision>\n"
                 f"    <scale>2</scale>\n    <required>{'true' if required else 'false'}</required>\n")

def percent(obj, name, label, default=None):
    d = f"    <defaultValue>{default}</defaultValue>\n" if default is not None else ""
    w(obj, name, f"    <label>{label}</label>\n    <type>Percent</type>\n    <precision>5</precision>\n"
                 f"    <scale>2</scale>\n    <required>false</required>\n{d}")

def checkbox(obj, name, label, default=False):
    w(obj, name, f"    <label>{label}</label>\n    <type>Checkbox</type>\n"
                 f"    <defaultValue>{'true' if default else 'false'}</defaultValue>\n")

def date(obj, name, label, default=None):
    d = f"    <defaultValue>{default}</defaultValue>\n" if default is not None else ""
    w(obj, name, f"    <label>{label}</label>\n    <type>Date</type>\n    <required>false</required>\n{d}")

def datetime_(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>DateTime</type>\n    <required>false</required>\n")

def email(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>Email</type>\n    <required>false</required>\n    <unique>false</unique>\n")

def phone(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>Phone</type>\n    <required>false</required>\n")

def location(obj, name, label):
    w(obj, name, f"    <label>{label}</label>\n    <type>Location</type>\n"
                 f"    <displayLocationInDecimal>true</displayLocationInDecimal>\n    <scale>6</scale>\n    <required>false</required>\n")

def picklist(obj, name, label, values, default_first=True):
    vals = "".join(
        f"            <value><fullName>{v}</fullName><default>{'true' if (i == 0 and default_first) else 'false'}</default><label>{v}</label></value>\n"
        for i, v in enumerate(values))
    w(obj, name, f"    <label>{label}</label>\n    <type>Picklist</type>\n    <required>false</required>\n"
                 f"    <valueSet>\n        <restricted>true</restricted>\n        <valueSetDefinition>\n            <sorted>false</sorted>\n{vals}"
                 f"        </valueSetDefinition>\n    </valueSet>\n")

def lookup(obj, name, label, target, relname, rellabel, filter_xml="", delete="SetNull"):
    w(obj, name, f"    <label>{label}</label>\n    <type>Lookup</type>\n    <referenceTo>{target}</referenceTo>\n"
                 f"    <relationshipName>{relname}</relationshipName>\n    <relationshipLabel>{rellabel}</relationshipLabel>\n"
                 f"    <deleteConstraint>{delete}</deleteConstraint>\n    <required>false</required>\n{filter_xml}")

def master_detail(obj, name, label, target, relname, rellabel):
    w(obj, name, f"    <label>{label}</label>\n    <type>MasterDetail</type>\n    <referenceTo>{target}</referenceTo>\n"
                 f"    <relationshipName>{relname}</relationshipName>\n    <relationshipLabel>{rellabel}</relationshipLabel>\n"
                 f"    <relationshipOrder>0</relationshipOrder>\n    <reparentableMasterDetail>false</reparentableMasterDetail>\n"
                 f"    <writeRequiresMasterRead>false</writeRequiresMasterRead>\n")

def formula(obj, name, label, ftype, expr, extra="", blanks="BlankAsZero"):
    esc = expr.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    w(obj, name, f"    <label>{label}</label>\n    <type>{ftype}</type>\n    <formula>{esc}</formula>\n"
                 f"    <formulaTreatBlanksAs>{blanks}</formulaTreatBlanksAs>\n{extra}")

def rollup(obj, name, label, child_obj, child_field, relname, filter_field=None):
    flt = (f"    <summaryFilterItems>\n        <field>{filter_field}</field>\n        <operation>equals</operation>\n"
           f"        <value>True</value>\n    </summaryFilterItems>\n") if filter_field else ""
    w(obj, name, f"    <label>{label}</label>\n    <type>Summary</type>\n"
                 f"    <summaryForeignKey>{child_obj}.{relname}</summaryForeignKey>\n    <summaryOperation>count</summaryOperation>\n{flt}")

def record_type_filter(obj_label, names):
    return ("    <lookupFilter>\n        <active>true</active>\n"
            f"        <errorMessage>Choose a {obj_label} account.</errorMessage>\n"
            "        <filterItems>\n            <field>Account.RecordType.DeveloperName</field>\n"
            f"            <operation>equals</operation>\n            <value>{names}</value>\n        </filterItems>\n"
            "        <isOptional>false</isOptional>\n    </lookupFilter>\n")

P, L, B = "RFP_Project__c", "RFP_Lane__c", "Benchmark_Rate__c"

# ---- RFP_Project__c
lookup(P, "Customer__c", "Customer", "Account", "RFP_Projects", "RFP Projects",
       record_type_filter("customer", "Customer, New_Customer"))
picklist(P, "Status__c", "Status", ["Draft", "Pricing", "Sent", "Awarded", "Lost"])
date(P, "Due_Date__c", "Due date")
percent(P, "Default_Margin__c", "Default margin %", default="15")
longtext(P, "Column_Mapping__c", "Column mapping (JSON)")
text(P, "Source_File_Name__c", "Source file name", 255)
longtext(P, "Notes__c", "Notes")
rollup(P, "Lane_Count__c", "Lanes", L, f"{L}.Id", "RFP_Project__c")
rollup(P, "Costed_Count__c", "Lanes with a cost", L, f"{L}.Id", "RFP_Project__c", f"{L}.Has_Cost__c")
rollup(P, "Sold_Count__c", "Lanes with a sell price", L, f"{L}.Id", "RFP_Project__c", f"{L}.Has_Sell__c")

# ---- RFP_Lane__c
master_detail(L, "RFP_Project__c", "RFP Project", P, "RFP_Lanes", "RFP Lanes")
number(L, "Row_Number__c", "Row number", 6, 0)
longtext(L, "Raw_Row__c", "Original row (JSON)")
for side in ("Origin", "Destination"):
    text(L, f"{side}_City__c", f"{side} city", 80)
    text(L, f"{side}_Province__c", f"{side} province/state", 80)
    text(L, f"{side}_Country__c", f"{side} country", 2)
    text(L, f"{side}_Postal__c", f"{side} postal", 12)
    lookup(L, f"{side}_Place__c", f"{side} place", "Pricing_Place__c", f"RFP_Lanes_{side}", f"RFP Lanes ({side})")
    checkbox(L, f"{side}_Resolved__c", f"{side} resolved")
text(L, "Mode__c", "Mode", 40)
text(L, "Equipment_Category__c", "Equipment category", 40)
text(L, "Equipment_Type__c", "Equipment type", 80)
text(L, "Commodity__c", "Commodity", 255)
number(L, "Quantity__c", "Quantity", 12, 2)
text(L, "Quantity_Unit__c", "Quantity unit", 20)
number(L, "Shipments_Per_Year__c", "Shipments per year", 8, 0)
checkbox(L, "Hazmat__c", "Hazmat")
number(L, "Customer_Fuel_Surcharge__c", "Customer fuel surcharge", 10, 2)
checkbox(L, "Customer_FSC_Included__c", "Customer FSC included")
number(L, "Hist_Count__c", "History count", 8, 0)
for n, lab in (("Hist_Min__c", "History min"), ("Hist_Median__c", "History median"),
               ("Hist_Average__c", "History average"), ("Hist_Max__c", "History max")):
    currency(L, n, lab)
text(L, "Hist_Precision__c", "History precision", 20, help="CITY, PROVINCE or RADIUS-50KM")
number(L, "Hist_Lookback_Days__c", "History lookback (days)", 5, 0)
datetime_(L, "Hist_As_Of__c", "History as of")
picklist(L, "Hist_Status__c", "History status", ["Pending", "Done", "Failed", "No match", "Unresolved"])
currency(L, "Cost__c", "Cost")
picklist(L, "Cost_Source__c", "Cost source", ["Bid", "History median", "Manual"], default_first=False)
lookup(L, "Selected_Bid__c", "Selected bid", B, "Selected_For_Lanes", "Selected for lanes")
percent(L, "Margin__c", "Margin %")
picklist(L, "Sell_Source__c", "Sell source", ["Margin", "Manual"])
currency(L, "Sell__c", "Sell")
longtext(L, "Notes__c", "Notes", 4000, 3)
formula(L, "Has_Cost__c", "Has cost", "Checkbox", "NOT(ISBLANK(Cost__c))", blanks="BlankAsBlank")
formula(L, "Has_Sell__c", "Has sell", "Checkbox", "NOT(ISBLANK(Sell__c))", blanks="BlankAsBlank")

# ---- Benchmark_Rate__c
lookup(B, "RFP_Lane__c", "RFP Lane", L, "Benchmark_Rates", "Benchmark Rates")
lookup(B, "RFP_Project__c", "RFP Project", P, "Benchmark_Rates", "Benchmark Rates")
lookup(B, "Carrier__c", "Carrier", "Account", "Benchmark_Rates", "Benchmark Rates",
       record_type_filter("carrier", "Carrier, New_Carrier"))
text(B, "Carrier_Name__c", "Carrier name (not in the system)", 255)
text(B, "Contact_Name__c", "Contact name", 120)
email(B, "Contact_Email__c", "Contact email")
phone(B, "Contact_Phone__c", "Contact phone")
formula(B, "Carrier_Display__c", "Carrier", "Text",
        "IF(ISBLANK(Carrier__c), Carrier_Name__c, Carrier__r.Name)")
currency(B, "Rate__c", "Rate", required=True)
currency(B, "Fuel_Surcharge__c", "Fuel surcharge")
checkbox(B, "FSC_Included__c", "FSC included")
number(B, "Transit_Days__c", "Transit days", 3, 0)
date(B, "Valid_From__c", "Valid from", default="TODAY()")
date(B, "Expires_On__c", "Expires on", default="TODAY() + 30")
formula(B, "Status__c", "Status", "Text", 'IF(Expires_On__c < TODAY(), "Expired", "Active")')
longtext(B, "Notes__c", "Notes", 4000, 3)
text(B, "Mode__c", "Mode", 40)
text(B, "Equipment_Category__c", "Equipment category", 40)
text(B, "Equipment_Type__c", "Equipment type", 80)
checkbox(B, "Hazmat__c", "Hazmat")
for side in ("Origin", "Destination"):
    text(B, f"{side}_City__c", f"{side} city", 80)
    text(B, f"{side}_Province__c", f"{side} province/state", 80)
    text(B, f"{side}_Country__c", f"{side} country", 2)
    text(B, f"{side}_Postal__c", f"{side} postal", 12)
    lookup(B, f"{side}_Place__c", f"{side} place", "Pricing_Place__c", f"Benchmark_Rates_{side}", f"Benchmark Rates ({side})")
    location(B, f"{side}_Geolocation__c", f"{side} geolocation")
text(B, "City_Lane__c", "City lane", 255, help='"City, ST:City, ST", as Revenova writes rtms__City_Lane__c')
text(B, "State_Lane__c", "State lane", 20, help='"ST:ST"')
text(B, "Zip3_Lane__c", "Zip3 lane", 20, help='"H7P:L1J"')
print("done")
