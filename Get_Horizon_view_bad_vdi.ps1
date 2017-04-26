#########################################################################################
#																						#
# Get List of Desktops that are not available or connected		 						#
# This is based on the script posted here:												#
# https://blogs.vmware.com/euc/2017/01/vmware-horizon-7-powercli-6-5.html				#
# Required:																				#
# Powercli 6.5 Release 1																#
# The VMware.Hv.Helper Module from https://github.com/vmware/PowerCLI-Example-Scripts	#
#																						#
#########################################################################################

#region variables
#########################################################################################
#								Variables												#
#	Password files need to be filled firs using:										#
#	Read-Host -AsSecureString | ConvertFrom-SecureString | Out-File 'filename.txt'		#
#	Enter password and press enter														#
#	vCenter things have been marked out but I left them in here 						#
#	because they might be usefull for when someone else uses this script				#
#########################################################################################
$cs = "connectionbroker"														# Horizon Connection Server
$hvcsUser= "Service_Account"													# User account to connect to Connection Server
$hvcsPassword = get-content .\hvcs_Credentials.txt | convertto-securestring		# Password for user to connect to Connection Server
$csDomain = "domain"															# Domain for user to connect to Connection Server
$hvedbpassword=get-content .\hvedb_Credentials.txt | convertto-securestring   	# password to access event database
$mailto="user@domain.com"														# Address to send the status mail to
$mailfrom="connectionbroker@domain.com"											# Address to send the mail from
$mailsubject="Overview bad VDI desktops"										# Mail subject
$smtpserver="mailserver.domain.com"												# Mail server			
#$vcuser="vcuser"																# User account to access the vCenter server
#$vcpassword=get-content .\vCenter_Credentials.txt | convertto-securestring		# password to access the vCenter server
#vc = "Enter vCenter name"														# vCenter Server



$baseStates = @('PROVISIONING_ERROR',
                'ERROR',
                'MAINTENANCE',
                'DISCONNECTED',
                'AGENT_UNREACHABLE',
                'AGENT_ERR_STARTUP_IN_PROGRESS',
                'AGENT_ERR_DISABLED',
                'AGENT_ERR_INVALID_IP',
                'AGENT_ERR_NEED_REBOOT',
                'AGENT_ERR_PROTOCOL_FAILURE',
                'AGENT_ERR_DOMAIN_FAILURE',
                'AGENT_CONFIG_ERROR',
                'UNKNOWN')
				

#endregion variables

#region initialize
###################################################################
#                    Initialize                                  #
###################################################################
# --- Import the PowerCLI Modules required ---
Import-Module VMware.VimAutomation.HorizonView
Import-Module VMware.VimAutomation.Core

# --- Connect to Horizon Connection Server API Service ---
$hvServer1 = Connect-HVServer -Server $cs -User $hvcsUser -Password $hvcsPassword -Domain $csDomain

# --- Get Services for interacting with the View API Service ---
$Services1= $hvServer1.ExtensionData

# --- Connect to the vCenter Server ---
#Connect-VIServer -Server $vc -User $vcUser -Password $vcPassword

# --- Connect to the view events database ---
$eventdb=connect-hvevent -dbpassword $hvedbpassword

#endregion initialize

#region html
###################################################################
#                    HTML                                         #
###################################################################

$style = "<style>BODY{font-family: Arial; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border: 1px solid black; background: #dddddd; padding: 5px; }"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style + "</style>"

#endregion

#region main
###################################################################
#                    Main                                        #
###################################################################
$Problemarray=@()
#Write-Output ""
if ($Services1) 
	{
     foreach ($baseState in $baseStates) 
		{
           # --- Get a list of VMs in this state ---
           $ProblemVMs = Get-HVMachineSummary -State $baseState

           foreach ($ProblemVM in $ProblemVMs) 
		   {
		   			$lastevent=get-hvevent -hvdbserver $eventdb -timeperiod 'day' -messagefilter $problemvm.base.name
			
				if ($lastevent.events){
					$lasteventtime=$lastevent.events | select -expandproperty eventtime -first 1
					$lasteventmessage=$lastevent.events | select -expandproperty message -first 1 
					$lasteventusername=$lastevent.events | select -expandproperty Username -first 1 
					}
				else{
				$lasteventtime="Last event is longer then 1 day ago"
				$lasteventmessage="Not Available"
				}
			$lastmaintenancedate=(Get-HVMachine -machinename $problemvm.base.name)
		   	$item = New-Object PSObject
			$item | Add-Member -type NoteProperty -Name Name -Value $problemvm.base.name 
			$item | Add-Member -type NoteProperty -Name State -Value $problemvm.base.basicstate 
			$item | Add-Member -type NoteProperty -Name Pool -Value $problemvm.namesdata.desktopname
			$item | Add-Member -type NoteProperty -Name Last_event_time -Value $lasteventtime
			$item | Add-Member -type NoteProperty -Name Last_event_user -Value $lasteventusername
			$item | Add-Member -type NoteProperty -Name Last_event_message -Value $lasteventmessage
			$Problemarray+= $item
           }
		}
	
		if ($problemarray)	
			{
			$mailbody=$Problemarray | sort state,name | convertto-html -head $style -property  name,state,Pool,Last_event_time,Last_event_user,Last_event_message | out-string
			send-mailmessage -smtpserver $smtpserver -to $mailto -from $mailfrom -subject $mailsubject -body $mailbody -bodyashtml 
			}
		else
			{
			send-mailmessage -smtpserver $smtpserver -to $mailto -from $mailfrom -subject $mailsubject -body "No problems found in the Horizon View Environment" 
			}

     Write-Output "Disconnect from Connection Server."
     Disconnect-HVServer -Server $cs -confirm:$false
		} 

else 
	{
     Write-Output "Failed to login in to Connection Server."
     
     }
# --- Disconnect from the vCenter Server ---
#Write-Output "Disconnect from vCenter Server."
#Disconnect-VIServer -Server $vc
#endregion main

