# nprinting
This project enables a user to make selections in a published QlikView document and then click a button that exports a text file containing those selections, which is then used to update an NPrinting filter and run an NPrinting task that applies that filter to a report.  That task can then email reports or save reports to a network folder, actions which are not available from the standard On-Demand reporting extension.

The basic setup is:
- define the fields that can be selected in the load script
- include a macro in the QlikView document that exports those selections as a text file
- have some mechanism that runs the Powershell script, either on a schedule or by using a filewatcher to watch for the selections file
- the Powershell script runs, loops through all of the selections files, updating the filter and running the task.  On completion of each loop it deletes the selections file.  You could change this to archive the files if needed.

There are two versions of the Powershell script to call the NPrinting API, one includes a certificate bypass for testing where the NPrinting server certificate is not setup correctly.  This should not be implemented in production.

Components for implementation:

The QlikView document needs to have the exportSelections macro.  This macro assumes a 7 character username, that might need to be changed.  It probably doesn't need the username, unless you want to archive the selections files for auditing.  The front-end chart that contains the selections is CH83 in the example below, that would need to be changed to the right chart ID.


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

The QlikView document needs to have an inline load script containing the fields that can be selected and their datatypes, and a variable created to list the fields.  For example:

NPrintingSelections:
load * inline [
name, type
Desk, text
Source, text
Date, number
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



The QlikView document needs to have a table created with the dimensions name and type and the measure value, defined as =Concat(distinct $(vSelectableFields), ';').  In the example macro above that table is CH83.

The QlikView document needs to have a button that runs the exportSelections macro.  If you want to disable the button until a different selection is made, create a variable called vExportedLatest and set the button's Enable condition to vExportedLatest = 0.  The button should have an action to set vExportedLatest to 1.  Add an onAnySelect trigger in Document Properties to set vExportedLatest to 0 when selections change (to reenable the button).

The QlikView document can have a text box containing a message saying that the report has been generated and will be emailed or saved to the relevant folder, only shown when vExportedLatest = 1.

NPrintingParameters.txt must exist in the same folder as RunNPrinting.ps1, or in a folder that is defined in the script, with contents in the following format:

server,selectionsfolder,appId,connectionId,filterId,filterName,taskId

NPrintingServer:4993,NPrintingSelectionsFolder,c6a927cf-ec08-4374-99cf-e734fadd87be,73b63e50-cfa0-4c7c-8208-28584ce6935c,f1f1f5b1-79fa-4d2b-8724-b609f0daf12e,Generic,50089a1c-a6d4-4752-8623-fad23a544ca9

You could also pass the location of the paramters file to the Powershell script as a command line argument, that would make the script more flexible.

NPrintingSelectionsFolder has the same value as vSelectionsPath in the macro.  That will ensure that the Powershell script picks up the selections from the folder where they are exported to.

The Powershell script takes the values in the selections file and builds the JSON body for the filter API call.  It updates the filter and then calls the NPrinting task.  You will need to have created the report, filter and task in NPrinting first.
