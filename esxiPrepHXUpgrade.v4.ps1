##################################################
# Prep an ESXi cluster for an HX upgrade. Useful if ESXi hosts have been hardened.
# hbazerma
##################################################

### Print clusters in numbered list. Verify cluster selection actually exists, otherwise ask again.
function clusterMenu {    
    Do {
        $global:clusterCheck = $false

        Try {
            Write-Host `n
            Write-Host -ForegroundColor Yellow "================ Select Cluster ================"
            Write-Host `n
            Write-Host -ForegroundColor Yellow "Please select a cluster to work with"     
            $global:clusters = Get-Cluster | Sort-object Name
            $i = 1
            $global:clusters | ForEach-Object {
                Write-Host $i".)" $_.Name; 
                $i++
            }
            
            Write-Host `n
            $global:ClusterSelect = Read-host -Prompt "Type the number of the cluster"
            $global:ClusterName = $global:clusters[$global:ClusterSelect - 1].Name
            
                
            ### Output selected cluster
            Write-Host `n
            Write-Host -ForegroundColor Yellow "You chose cluster: " -NoNewLine
            Write-Host -ForegroundColor Magenta "$global:ClusterName"    

            ### Get information about all hosts in the defined cluster        
            $global:vmHosts = Get-Cluster -Name $global:ClusterName -ErrorAction Stop | Get-VMHost | 
            Where-Object { $global:vmHosts.ConnectionState -eq "Connected" } | 
            Sort-Object
        }
        
        Catch {
            Write-Host -ForegroundColor Red -BackgroundColor Black "You chose an invalid cluster name. Did you Typo?" `n    
            $global:clusterCheck = $true
        }
    } 

    while ($global:clusterCheck)
}


Write-Host `n "This will allow you to enable/disable SSH, timeouts, and ESXi lockdown mode for all hosts in a given cluster."

### Prompt user for vCenter Server name, and connect to it
$vCenterServer = Read-Host -Prompt 'FQDN of vCenter'

### This Try/Catch statement will quit on a fat finger of vCenter FQDN.
Try {
    Connect-VIServer -Server $vCenterServer -ErrorAction Stop | Out-Null        
}

Catch {
    Write-Host -ForegroundColor Red -BackgroundColor Black "Could not connect to the vCenter Server [$vCenterServer]. Did you Typo?" `n
    Exit
}

##Call menu function
clusterMenu


$global:vmHosts = Get-Cluster -Name $global:ClusterName -ErrorAction Stop | Get-VMHost | 
Where-Object { $_.ConnectionState -eq "Connected" } | Sort-Object
$cont = ""
Do {
    ### Menu driven task select
    Write-Host `n
    Write-Host -ForegroundColor Yellow "Please enter a task to perform on each host in the " -NoNewLine
    Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
    Write-Host -ForegroundColor Yellow " cluster:"
    Write-Host "1.)  Unmount ISO from cluster VM's"
    Write-Host "2.)  Enable SSH"
    Write-Host "3.)  Disable SSH timeout"
    Write-Host "4.)  Set SSH to start and stop automatically with host"
    Write-Host "5.)  Disable Lockdown Mode"    
    Write-Host "6.)  Disable SSH"    
    Write-Host "7.)  Enable SSH timeout"    
    Write-Host "8.)  Set SSH to start and stop manually"
    Write-Host "9.)  Enable Lockdown Mode"
    Write-Host "10.) Select different cluster"
    Write-Host "11.) Restart management agent on host"
    Write-Host "12.) Exit" `n
    $choice = Read-Host -Prompt "Please select an option"

    ### Do the thing
    Switch ($choice) {

        ### Check and unmount ISO from VM's where present in the cluster
        1 {
            Write-Host -ForegroundColor Yellow `n "Checking all VMs in the " -NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster to see if there are mounted ISO files."
            Write-Host -ForegroundColor Yellow `n "This may take some time!!!" `n
            Write-Host -ForegroundColor Yellow "  ;)( ;"
            Write-Host -ForegroundColor Yellow " :----:"
            Write-Host -ForegroundColor Yellow "C|====|"
            Write-Host -ForegroundColor Yellow " |    |"
            Write-Host -ForegroundColor Yellow " ``----'"

            
            ### Create VMs array
            $VMs = @()

            ### Get VMs
            $thisVMs = Get-VM

            #Get VM information
            ForEach ($vm in $thisVMs) {
                

                if ( (($vm | Get-CDDrive).ISOPath) -or (($vm | Get-CDDrive).RemoteDevice) -or (($vm | Get-CDDrive).HostDevice) ) {
                    ###Setup status output
                    $VMInfo = "" | Select-Object "VM", "Host", "ISO", "RemoteDevice", "HostDevice"                               

                    ###Define VM name, ESXi host and ISO path. Only printing VM name for status
                    $VMInfo."VM" = $vm.Name
                    $VMInfo."Host" = ($vm | Get-VMHost).Name
                    $VMInfo."ISO" = ($vm | Get-CDDrive).ISOPath
                    $VMInfo."RemoteDevice" = ($vm | Get-CDDrive).RemoteDevice
                    $VMInfo."HostDevice" = ($vm | Get-CDDrive).HostDevice

                    #Add VM info to array
                    $VMs += $VMInfo
                }

                $counter++;
                
                ## Print progress
                if ( $counter % 10 -eq 0 ) {                    
                    Write-Host "Checked $counter of" $thisVMs.length "VM's in " -NoNewline                    
                    Write-Host -ForegroundColor Magenta "$ClusterName"
                }                
            }            

            #Prompt and eject CDROM
            Write-Host -ForegroundColor Yellow "Found " $VMs.length " mappings"
            $answer = Read-Host "Eject now? (y/n)"
            if ($answer -eq "y") {
                ForEach ($vm in $VMs) {
                    Write-Host "Ejecting CD drive on " -NoNewLine
                    #Write-Host -ForegroundColor Yellow "$vm.VM" -NoNewLine
                    Write-Host -ForegroundColor Yellow $vm.VM -NoNewLine
                    Write-Host " ..."
                    Get-VM $vm.VM | Get-CDDrive | Set-CDDrive -NoMedia -Confirm:$false | Out-Null
                }
                Write-Host -ForegroundColor Green "Done!"
            }
            else {                 
                Write-Host -ForegroundColor Yellow "Exiting..." 
            }
            $cont = $true                     
        }
        
        ### Enable SSH on all hosts in the cluster
        2 {
            Write-Host -ForegroundColor Yellow `n "Enabling SSH on all hosts in the " -NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"
            ForEach ($global:vmHost in $global:vmHosts) {
                
                Try {
                    Start-VMHostService -HostService ($global:vmHost |
                        Get-VMHostService | Where-Object { $_.key -eq "TSM-SSH" }) -Confirm:$false |                               
                    Out-Null
                    Write-Host "SSH is" -NoNewLine
                    Write-Host -ForegroundColor Green " running " -NoNewLine
                    Write-Host "on " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost"
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't enable SSH on $vmhost :("    
                }                
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }

        ### Disable SSH timeout on all hosts in the cluster. Restarts SSH service for setting to take effect.
        3 {
            Write-Host -ForegroundColor Yellow `n "Disabling SSH timeout on all hosts in the " -NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"`n
            ForEach ($global:vmHost in $global:vmHosts) {
                
                Try {
                    Get-VMHost $global:vmHosts | Where-Object { $_.ConnectionState -eq "Connected" } | 
                    Get-AdvancedSetting -Name 'UserVars.ESXiShellTimeOut' | 
                    Set-AdvancedSetting -Value "0" -Confirm:$false | Out-Null                               
                    Write-Host "SSH timeout disabled on     " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost"
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't disable SSH timeout on $vmhost :("
                }   
                
                Try {
                    Restart-VMHostService -HostService ($global:vmHosts | Where-Object { $_.ConnectionState -eq "Connected" } |
                        Get-VMHostService | Where-Object { $_.key -eq "TSM-SSH" }) -Confirm:$false | Out-Null
                    Write-Host "Restarting SSH on           " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost" 
                }   
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't restart SSH service on $vmhost :("
                }
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }
        
        ### Set SSH policy to start/stop with host.
        4 {
            Write-Host -ForegroundColor Yellow `n "Enabling SSH to start and stop with hosts in the "-NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"
            ForEach ($global:vmHost in $global:vmHosts) {
                
                Try {
                    Get-VMHost $global:vmHost | Get-VMHostService | Where-Object { $_.key -eq "TSM-SSH" } | 
                    Set-VMHostService -policy "On" | Out-Null
                    Write-Host "SSH set to automatically start/stop with " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost"
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't set SSH policy on $vmhost :("
                }                
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }
        
        ### Disable Lockdown Mode on all hosts in the cluster
        5 {
            Write-Host -ForegroundColor Yellow `n "Disabling Lockdown Mode on all hosts in the "-NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"
            ForEach ($global:vmHost in $global:vmHosts) {                
                
                Try {
                    (Get-VMHost $vmhost | Get-View).ExitLockdownMode()
                    Write-Host -ForegroundColor Green "Lockdown disabled for $vmhost" 
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Can't disable Lockdown Mode for $vmhost it's probably already disabled."
                }
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }
		
        ### Disable SSH on all hosts in the cluster
        6 {
            Write-Host -ForegroundColor Yellow `n "Disabling SSH on all hosts in the "-NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"
            ForEach ($global:vmHost in $global:vmHosts) {                
                
                Try {                                    
                    Stop-VMHostService -HostService ($global:vmHost |
                        Get-VMHostService | Where-Object { $_.key -eq "TSM-SSH" }) -Confirm:$false |                               
                    Out-Null
                    Write-Host "SSH is" -NoNewLine
                    Write-Host -ForegroundColor Yellow " stopped " -NoNewLine
                    Write-Host "on " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost"
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't disable SSH on $vmhost :("    
                }
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }

        ### Enable SSH timeout (600 seconds) on all hosts in the cluster. Restarts SSH service for setting to take effect.
        7 {
            Write-Host -ForegroundColor Yellow `n "Setting SSH timeout to 600 seconds on all hosts in the "-NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"
            ForEach ($global:vmHost in $global:vmHosts) {                
                Try {
                    Get-VMHost $global:vmHosts | Where-Object { $_.ConnectionState -eq "Connected" } | 
                    Get-AdvancedSetting -Name 'UserVars.ESXiShellTimeOut' | 
                    Set-AdvancedSetting -Value "600" -Confirm:$false | Out-Null                               
                    Write-Host "SSH timeout enabled on     " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost"
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't enable SSH timeout on $vmhost :("
                }   
                
                Try {
                    Restart-VMHostService -HostService ($global:vmHosts | Where-Object { $_.ConnectionState -eq "Connected" } |
                        Get-VMHostService | Where-Object { $_.key -eq "TSM-SSH" }) -Confirm:$false | Out-Null
                    Write-Host "Restarting SSH on           " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost" 
                }   
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't restart SSH service on $vmhost :("
                }
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }
        
        ### Set SSH policy to start/stop manually.
        8 {
            Write-Host -ForegroundColor Yellow `n "Enabling SSH to start and manually on all hosts in the "-NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"
            ForEach ($global:vmHost in $global:vmHosts) {
                
                Try {
                    Get-VMHost $global:vmHost | Get-VMHostService | Where-Object { $_.key -eq "TSM-SSH" } | 
                    Set-VMHostService -policy "Off" | Out-Null
                    Write-Host "SSH set to manual start/stop on " -NoNewLine
                    Write-Host -ForegroundColor Yellow "$vmHost"
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Couldn't set SSH policy on $vmhost :("
                }                
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }
        
        ### Enable ESXi lockdown Mode on all hosts in the cluster
        9 {			
            Write-Host -ForegroundColor Yellow `n "Disabling Lockdown Mode on all hosts in the "-NoNewLine
            Write-Host -ForegroundColor Magenta "$ClusterName" -NoNewLine
            Write-Host -ForegroundColor Yellow " cluster:"
            ForEach ($global:vmHost in $global:vmHosts) {                
                
                Try {
                    (Get-VMHost $vmhost | Get-View).EnterLockdownMode()
                    Write-Host -ForegroundColor Green "Lockdown enabled for $vmhost" 
                }
                
                Catch {
                    Write-Host -ForegroundColor Red "Can't enable Lockdown Mode for $vmhost it's probably already enabled :("
                }
            }
            Write-Host -ForegroundColor Green "Done!"
            $cont = $true
        }

        ### choose new cluster
        10 {            
            clusterMenu
            $cont = $true
        }
        
        ### Restart management agent on host
        11 {
            Do {
                $hostCheck = $false
                $continue = $true

                ### Print hosts from cluster in numbered list. Verify cluster selection actually exists, otherwise ask again.

                Try {
                    Write-Host `n
                    Write-Host -ForegroundColor Yellow "Please select a host to work with"                                             
                    $vmHostMenu = Get-Cluster $ClusterName | Get-VMHost | Select-Object Name | Sort-object Name
                    $i = 1
                    $vmHostMenu | ForEach-Object {
                        Write-Host $i".)" $_.Name; 
                        $i++
                    }
                    Write-host "q to exit to menu"
                    Write-Host `n
                    $vmHostList = Read-host -Prompt "Type the number of the host"
                    $vmHostSelect = $vmHostMenu[$vmHostList - 1].Name                                 
                    Write-Host `n
                    
                    ### If a host that doesn't exist is selected, $vmHostSelect will be $null. If $null prompt user.
                    if ($null -eq $vmHostSelect) {
                        $hostCheck = $true
                        Write-Host -ForegroundColor Red -BackgroundColor Black "Invalid host selected. Did you Typo?"
                        $continue = $false
                    }

                    else {
                        ### Output selected host
                        Write-Host -ForegroundColor Yellow "You chose host: " -NoNewLine
                        Write-Host -ForegroundColor Magenta "$vmHostSelect"
                        $continue = $true
                        Try {
                            ### Restart vpxa service on selected host
                            Get-VMHostService -VMHost $vmHostSelect | Where-Object { $_.Key -eq "vpxa" } | Restart-VMHostService -ErrorAction SilentlyContinue
                            Write-Host -ForegroundColor Green "Done!"
                        }

                        Catch {                            
                            Write-Host -ForegroundColor Red "Unable to restart vCenter management agent on $vmHostSelect :("                            
                        }                    
                    }                    
                }
                Catch {
                    ### When q is selected
                    Write-Host -ForegroundColor Yellow "Exiting..."
                }                        
            }             
            while ($hostCheck)                  
            $cont = $true
        }
        ### Exit the script
        12 {
            Write-Host -ForegroundColor Green "All done!"
            $cont = $false
        }
       
        ### If user enters anything else
        default {
            Write-Host -ForegroundColor Red ">>> Invalid input. Please select a valid option."
            $cont = $true
        }
    }
}

### Loop through the script until task #7 (Exit) is chosen
While ($cont)

### Disconnect from the vCenter Server
Disconnect-VIServer -Server $vCenterServer -Confirm:$false | Out-Null