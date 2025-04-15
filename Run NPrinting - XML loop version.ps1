function Create-FieldObject {
    param (
        [string]$connectionId,
        [string]$name,
        [string]$value
    )

    $valueObject = New-Object PSObject
    $valueObject | Add-Member -Type NoteProperty -Name "value" -Value $value
    if ([double]::TryParse($value, [ref]0)) {
        $valueObject | Add-Member -Type NoteProperty -Name "type" -Value 'number'
    } else {
        $valueObject | Add-Member -Type NoteProperty -Name "type" -Value 'text'
    }

    $field = New-Object PSObject
    $field | Add-Member -Type NoteProperty -Name "connectionId" -Value $connectionId
    $field | Add-Member -Type NoteProperty -Name "name" -Value $name
    $field | Add-Member -Type NoteProperty -Name "values" -Value @($valueObject)

    return $field
}

# Define the required fields
$requiredFields = @('Frequency', 'NumdBusinessDate')

foreach ($record in $xml.records.record) {
    # Find the fm_RunStatus element
    $runStatus = $record.value | Where-Object { $_.name -eq "fm_RunStatus" }
    $runResult = $record.value | Where-Object { $_.name -eq "fm_RunResult" }
    if ($runStatus.'#text' -eq "2") {
        # Split the key field into variables
        $keyParts = $record.key -split '\|\|'

        # Create a hashtable to store the dynamic variables
        $dynamicVars = @{}

        # Assign values to the dynamic variables based on the required fields
        for ($i = 0; $i -lt $requiredFields.Count; $i++) {
            $fieldName = $requiredFields[$i]
            $dynamicVars[$fieldName] = $keyParts[$i]
        }

        # Convert filter fields to JSON
        $fields = @()

        foreach ($fieldName in $requiredFields) {
            $value = $dynamicVars[$fieldName]
            if ($value) {
                $fields += Create-FieldObject -connectionId $connectionId -name $fieldName -value $value
            }
        }
    }
}