# nprinting
Powershell script to call the NPrinting API

Components for implementation:

QlikView document needs to have the exportSelections macro.  This macro assumes a 7 character username, that might need to be changed.  The front-end chart that contains the selections is CH83 in the example below, that will need to be changed.

sub exportSelections

vUsername = right(ActiveDocument.Evaluate("OsUser()"),7)
vSelectionsPath = ActiveDocument.Variables("vSelectionsPath").GetContent.String

set table = ActiveDocument.GetSheetObject( "CH83" )

for RowIter = 0 to table.GetRowCount-1
    for ColIter =0 to table.GetColumnCount-1
        set cell = table.GetCell(RowIter,ColIter)
        if ColIter < table.GetColumnCount-1 then vDelimiter = "," else: vDelimiter = ""
        vContent = vContent  & cell.Text  & vDelimiter
    next
    vContent = vContent & chr(10)
next

set fso = CreateObject("Scripting.FileSystemObject")
set File = fso.OpenTextFile(vSelectionsPath & "\Selections-" & vUsername & "-" & year(date()) & right("0" & month(date()),2) & right("0"&day(date()),2) & right("0" & hour(time()),2) & right("0" & minute(time()),2) & right("0" & second(time()),2) & ".csv", 2, true)

File.Writeline vContent
File.Close

end sub

The vSelectionsPath variable needs to be defined in the load script.

QlikView document needs to have an inline load script containing the fields that can be selected and their datatypes, and a variable created to list the fields.

NPrintingSelections:
load * inline [
name, type
ParentDesk, text
Day, number
];

fields1:
LOAD 
    Concat(chr(39) & name & chr(39), ', ') as Field1,
    Concat(chr(34) & name & chr(34), ', ') as Field2
resident NPrintingSelections;

let vField1 = FieldValue('Field1', 1);
let vField2 = FieldValue('Field2', 1);

set vSelectableFields = pick(match(name, $(vField1)), $(vField2));

drop Table fields1;



QlikView document needs to have a table created with the dimensions name and type and the measure value, defined as =Concat(distinct $(vSelectableFields), ';').  In the example macro above that table is CH83.

QlikView document needs to have a button that runs the exportSelections macro.  If you want to disable the button until a different selection is made, create a called vExportedLatest and set the button's Enable condition set to vExportedLatest = 0.  The button should have an action to set vExportedLatest to 1.  Add an onAnySelect trigger in Document Properties to set vExportedLatest to 0 when selections change (to reenable the button).

QlikView document can have a text box containing a message saying that the report has been generated and will be saved to the relevant folder, only shown when vExportedLatest =1.

NPrintingParameters.txt must exist in the same folder as RunNPrinting.ps1, with contents in the following format:

server,selectionsfolder,appId,connectionId,filterId,filterName,taskId
https://NPrintingServer:4993,NPrintingSelectionsFolder,c6a927cf-ec08-4374-99cf-e734fadd87be,73b63e50-cfa0-4c7c-8208-28584ce6935c,f1f1f5b1-79fa-4d2b-8724-b609f0daf12e,Generic,50089a1c-a6d4-4752-8623-fad23a544ca9

NPrintingSelectionsFolder has the same value as vSelectionsPath in the macro.
