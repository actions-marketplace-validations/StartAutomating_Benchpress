function Get-Benchmark
{
    <#
    .Synopsis
        Gets benchmark files.
    .Description
        Gets benchmark script files and benchmark input files.
    .Example
        Get-Benchmark -BenchmarkPath a.benchmark.ps1
    .Link
        Measure-Benchmark
    .Link
        Checkpoint-Benchmark
    #>
    [CmdletBinding(DefaultParameterSetName='CurrentDirectory')]
    [OutputType([PSObject])]
    param(
    # The path to the benchmark file
    [Parameter(Mandatory=$true,ParameterSetName='Path',ValueFromPipelineByPropertyName=$true,Position=0)]
    [ValidatePattern('\.benchmark\.(psd1|ps1|clixml|csv|json)$')]
    [Alias('Fullname')]
    [string[]]
    $BenchmarkPath,
    # The name of a module
    [Parameter(Mandatory=$true,ParameterSetName='Module',ValueFromPipelineByPropertyName=$true)]
    [string]
    $ModuleName
    )
    process {
        #region Find Module Benchmarks
        if ($PSCmdlet.ParameterSetName -eq 'Module') { # If we want a module's benchmarks
            $loadedModules = Get-Module # find all loaded modules
            $theModule = foreach ($_ in $loadedModules) { # then find this module.
                if ($_.Name -eq $ModuleName) { $_ }
            }
            if (-not $theModule) { # If we couldn't, write and error and bounce.
                Write-Error "Could not find module $ModuleName.  It may not be loaded"
                return
            }


            $theModule | # Go to the module's
                Split-Path | # root directory
                Get-ChildItem -Recurse -Filter *.benchmark.* | # get all benchmark files
                Where-Object -Property Name -Match "(psd1|ps1|clixml|csv|json)$" |# of the right extension
                Get-Benchmark # and pipe them to Get-Benchmark

            return
        }
        #endregion Find Module Benchmarks
        # If we want benchmarks from the current directory
        if ($PSCmdlet.ParameterSetName -eq 'CurrentDirectory') {
            Get-ChildItem -Recurse -Filter *.benchmark.* | # get all benchmark files
                Where-Object -Property Name -Match "(psd1|ps1|clixml|csv|json)$" | # of the right extension
                Get-Benchmark # and pipe them to Get-Benchmark
            return
        }
        if ($PSCmdlet.ParameterSetName -eq 'Path') { # If want benchmark information for a particular file(s)
            foreach ($bp in $benchmarkPath) {
                # try to resolve it's path
                $resolvedBenchmarkPath = $ExecutionContext.SessionState.Path.GetResolvedPSPathFromPSPath($bp)
                # If we couldn't, return.
                if (-not $resolvedBenchmarkPath)  { return }
                # Get the actual benchmark file
                $benchmarkFile = Get-Item -LiteralPath $resolvedBenchmarkPath
                # Determine it's extension and short name
                $benchmarkFullExtension = '.benchmark' + $benchmarkFile.Extension
                $benchmarkFileName = $benchmarkFile.Name.Substring(0,
                    $benchmarkFile.Name.Length - $benchmarkFullExtension.Length) -replace '_', ' '

                if ($benchmarkFile.Extension -eq '.ps1') { # If it's a .PS1
                    # we return a pointer to the file
                    $benchmarkCmd = $ExecutionContext.SessionState.InvokeCommand.GetCommand($benchmarkFile.FullName, 'ExternalScript')
                    $benchmarkCmd |
                        Add-Member NoteProperty FileName $benchmarkFileName -Force -PassThru |
                        Add-Member NoteProperty FilePath $benchmarkFile.FullName -Force -PassThru
                    return
                }

                # Otherwise, we load the benchmark data
                $benchmarkInput =
                    if ($benchmarkFile.Extension -eq '.psd1') # .psd1s get treated as a data blocks
                    {
                        & ([ScriptBlock]::Create("data { $([IO.File]::ReadAllText($benchmarkFile.FullName))}")) |
                            & {
                                process {
                                    if ($_ -is [string]) {
                                        @{Command=$_}
                                    } else {
                                        $_
                                    }

                                }
                            }
                    }
                    elseif ($benchMarkFile.Extension -eq '.json') { # .json gets treated as JSON
                        [IO.File]::ReadAllText($benchmarkFile.FullName) | ConvertFrom-Json
                    }
                    elseif ($benchMarkFile.Extension -eq '.clixml') { # .clixml gets imported
                        $benchmarkFile | Import-Clixml
                    }
                    elseif ($benchMarkFile.Extension -eq '.csv') { # .csv gets imported
                        $benchmarkFile | Import-Csv
                    }
                if (-not $benchmarkInput) { # If we don't have any benchmark data
                    Write-Error "$bp did not contain benchmarks" # error
                    return # and bounce.
                }
                # Now we have to fix the benchmark data
                foreach ($benchmark in $benchmarkInput) {

                    if ($benchMark -is [Collections.IDictionary]) { # If the benchmark is a hashtable
                        $benchmark = New-Object PSObject -Property $benchmark # turn it into a property bag.
                    }
                    # If the .Technique property was not a hashtable
                    if ($benchmark.Technique -isnot [Collections.IDictionary]) {
                        # make it one
                        $technique = [Ordered]@{}
                        foreach ($prop in $benchmark.Technique.psobject.properties) {
                            $technique[$prop.Name] = $prop.Value
                        }
                        if ($technique.Count) {
                            # and overwrite the original technique property
                            $benchmark | Add-Member NoteProperty Technique $technique -Force
                        }
                    }
                    if ($benchmark.ScriptBlock -and $benchmark.ScriptBlock -isnot [ScriptBlock]) {
                        $benchmark.ScriptBlock = [ScriptBlock]::Create($benchmark.ScriptBlock)
                    }
                    # Return the benchmark, with the short file name
                    $benchmark  |
                        Add-Member NoteProperty FileName $benchmarkFileName -Force -PassThru |
                        Add-Member NoteProperty FilePath $benchmarkFile.FullName -Force -PassThru
                }
            }
        }
    }
}
