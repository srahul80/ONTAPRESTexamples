  

### Trust self signed SSL certificate

Add-Type @"
   using System.Net;
   using System.Security.Cryptography.X509Certificates;
   public class TrustAllCertsPolicy : ICertificatePolicy {
   public bool CheckValidationResult(
   ServicePoint srvPoint, X509Certificate certificate,
   WebRequest request, int certificateProblem) {
      return true;
   }
}
"@
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls12'
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

#############################################
##################### Variables
############################################

$user="admin"
$pwd="Netapp1!"
$clusterIP="cluster1"
$clusterDRIP="cluster2"
$svmname="svm_NWM_demo1"


########################################
#################### Login details
####################################
$password = ConvertTo-SecureString $pwd -AsPlainText -Force
$mycred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user,$password

 $headers = @{   
 Accept       = "application/json"
 }
  
 $headjson = $headers   
 
 $uri="https://$($clusterIP)/api/cluster" 
 
  try{    
  
      write-host "Connect to ONTAP Cluster " -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri -Headers $headjson -Credential $mycred -Method GET  -ContentType "application/json" -ErrorAction Stop   
      write-host "Connected to Cluster : $($response.name)" -ForegroundColor green
      write-host ($response | Out-String) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to login to ONTAP cluster" $_
   } 



 
 #####################
   ########## Break SM-S relationsihp'####
   ###############################

   $svmname_sm=$svmname+ "_sm" 
$i=1
$maxcount=3
do{
      
$flexVol_sm=$svmname_sm+ "_vol" + $i
$uri_svmsm_update="https://$($clusterDRIP)/api/snapmirror/relationships" 
$dest_path= "$($svmname_sm):$($flexvol_sm)" 

try{    
      $response_uuid = Invoke-RestMethod -Uri "$($uri_svmsm_update)?destination.path=$($dest_path)" -Headers  $headjson  -Credential $mycred -Method GET   -ContentType "application/json" -ErrorAction Stop   
      write-host "UUID for SM relationships with destination $($dest_path) is  $($response_uuid.records.uuid)"
      
      
      
      ####################################
      ####Queiese and Break the SM relationship 
      ###################################
      
      
      $sm_pause=@{

      state = "paused"
      }
    #start-sleep -Seconds 3
        

      $sm_pause_json=$sm_pause | ConvertTo-Json
      write-host $sm_init_json
      write-host "REST CAll .. $($uri_svmsm_update)/$($response_uuid.records.uuid)" -BackgroundColor blue 
      write-host "Start SnapMirror quiesece for ..$($dest_path) " -BackgroundColor blue 
      $response_q = Invoke-RestMethod -Uri "$($uri_svmsm_update)/$($response_uuid.records.uuid)/" -Headers $headjson -Credential $mycred -Method PATCH -body $sm_pause_json  -ContentType "application/json" -ErrorAction Stop   
      write-host "SM-S relationship quieseced : $($response_q)" -ForegroundColor green
      Start-Sleep -Seconds 5
      $sm_break=@{

      state = "broken_off"
      }
      $sm_break_json=$sm_break | ConvertTo-Json
      write-host "Start SnapMirror break for ..$($dest_path) " -BackgroundColor blue 
      $response_b = Invoke-RestMethod -Uri "$($uri_svmsm_update)/$($response_uuid.records.uuid)/" -Headers $headjson -Credential $mycred -Method PATCH -body $sm_break_json  -ContentType "application/json" -ErrorAction Stop   
      write-host "SM-S relationship broken : $($response_q)" -ForegroundColor green
   }
   catch
   {  
     write-host "Unable to break SVM-S relationship " $_
   } 

   $i++

}while ( $i -le $maxcount)
  


