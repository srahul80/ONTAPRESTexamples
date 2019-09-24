 

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

$user="admin"  #######cluster Admin
$pwd="Netapp1234!" ######### Password  - This could be 
$clusterIP="cluster1" ## Primary Cluster Name
$clusterDRIP="cluster2" ## Secondary/DR Cluster Name

######## SVM name and details to provision new SVM
$svmname="svm_prd3"
$lifname=$svmname+"_datalif1"
$lifIP="192.168.0.190"
$lifnetmask ="24"
$homeport="e0d"
$homenode="cluster1-01"

######### Volume provisioning details 
$aggrname="aggr1_01"
$aggrname_dr="aggr1_01"



############ Create Cred object 

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


  
################################################
############### Create a NAS SVM on prod #######
################################################


$uri="https://$($clusterIP)/api/svm/svms" 

$body=@{
       name =$svmname
       nfs =@{
       enabled="true"}
       dns= @{
domains =@("demo.netapp.com")
servers =@("192.168.0.253")
}

}

$createsvm=$body | ConvertTo-Json
Write-Host $body -ForegroundColor gray 
  try{    
  
      write-host "Creating new SVM " -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri -Headers $headjson -Credential $mycred -Method POST -body $createsvm  -ContentType "application/json" -ErrorAction Stop   
      write-host "SVM Created : $($response.job)" -ForegroundColor green
      write-host ($response.records | Out-String) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create SVM" $_
     exit 
   } 

Start-Sleep -Seconds 15

 ##########################################
 ############## Create LIF
 ##########################################



$lifcreate= @{
  enabled= "true"
  ip=@{
    address = $lifIP
    netmask = $lifnetmask
  }
  ipspace =@{
    name= "Default"
     }
  location =@{
    auto_revert= "true"
    broadcast_domain = @{
      name = "Default"
     }
    failover = "home_port_only"
    home_port = @{
      name = $homeport
      node =@{
        name = $homenode
      }
      }
      }
  name = $lifname
  scope = "svm"
  service_policy = @{
    name = "default-data-files"
    }
  svm = @{
    name =$svmname
      }
  }
  

  $lifjson=$lifcreate | ConvertTo-Json -Depth 4
  
       $uri_lif="https://$($clusterIP)/api/network/ip/interfaces" 
  write-host $lifjson -ForegroundColor gray 
  try{    
  
      write-host "Creating new LIF $($lifname) on SVM $($svmname)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_lif -Headers $headjson -Credential $mycred -Method POST -body $lifjson  -ContentType "application/json" -ErrorAction Stop   
      write-host "LIF Created : $($response)" -ForegroundColor green
     }
   catch
   {  
     write-host "Unable to create LIF " $_
   } 


   
##########################################
############ Create FlexVol###############
##########################################
$i=1
$maxcount=3
do{
      $flexVol=$svmname+ "_vol" + $i
      write-host $flexVol

       $uri_flexvol="https://$($clusterIP)/api/storage/volumes" 

       $bodyflexvol=@{
       name =$flexVol
       size= "10GB"
       guarantee=@{
       type ="none"
       }
       svm = @{
       name=$svmname
       }
       aggregates= @(@{
       name= $aggrname 
       })
        efficiency=@{
            compression= "background"
            dedupe = "background"
        }
        nas = @{
                 export_policy= @{
                 name ="default"
                }
    
                path= "/$($flexvol)"
                security_style ="unix"
              }
}
$createFlexVol=$bodyflexvol | ConvertTo-Json
write-host $createFlexVol
  try{    
  
      write-host "Creating new FlexVol $($flexVol) on SVM $($svmname)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_flexvol -Headers $headjson -Credential $mycred -Method POST -body $createFlexVol  -ContentType "application/json" -ErrorAction Stop   
      write-host "FlexVol Created : $($response.job.uuid)" -ForegroundColor green
      write-host ($response.job) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create FlexVol" $_
   } 
   $i++
   Write-Host $i
   }while($i -le $maxcount)



################################################################
############### Create a NAS SVM on DR SnapMirror Async #######
################################################################

$svmname_sm=$svmname+ "_sm"
$uri_svm_sm="https://$($clusterDRIP)/api/svm/svms" 

$body_svm_sm=@{
       name =$svmname_sm
       nfs =@{
       enabled="true"}
       dns= @{
domains =@("lab.netapp.com")
servers =@("192.168.0.220")
}

}

$createsvm_sm=$body_svm_sm | ConvertTo-Json
Write-Host $body -ForegroundColor gray 
  try{    
  
      write-host "Creating new SVM $($svmname_sm)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_svm_sm -Headers $headjson -Credential $mycred -Method POST -body $createsvm_sm  -ContentType "application/json" -ErrorAction Stop   
      write-host "SVM Created : $($response.job)" -ForegroundColor green
      write-host ($response.records | Out-String) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create SVM on DR cluster" $_
     exit 
   } 

   Start-Sleep -Seconds 10




##########################################
############ Create FlexVol for SM Async ###############
##########################################
##########################################
$i=1
$maxcount=3
do{
      
      $flexVol_sm=$svmname_sm+ "_vol" + $i
      write-host $flexVol_sm

       $uri_flexvol="https://$($clusterDRIP)/api/storage/volumes" 

       $bodyflexvol_sm=@{
       name =$flexVol_sm
       size= "10GB"
       guarantee=@{
       type ="none"
       }
       svm = @{
       name=$svmname_sm
       }
       type = "dp"
       aggregates= @(@{
       name= $aggrname_dr
       })
        
  }
      

  $createFlexVol_sm=$bodyflexvol_sm | ConvertTo-Json

  write-host $createFlexVol
  try{    
  
      write-host "Creating new FlexVol $($flexVol) on SVM $($svmname)" -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_flexvol -Headers $headjson -Credential $mycred -Method POST -body $createFlexVol_sm  -ContentType "application/json" -ErrorAction Stop   
      write-host "FlexVol Created : $($response.job.uuid)" -ForegroundColor green
      write-host ($response.job) -ForegroundColor Green
   }
   catch
   {  
     write-host "Unable to create FlexVol" $_
   } 
   $i++
   Write-Host $i
   }while($i -le $maxcount)


###########################################
############## Peer new SVM
###########################################
$uri_peer_create="https://$($clusterDRIP)/api/svm/peers" 

       $svm_peer_create=@{
           
      peer = @{
      cluster =@{
      name=$clusterIP
      }
      svm =@{
      name=$svmname
      }
      }
      applications= @(
      "snapmirror"
      )

      svm=@{
      name=$svmname_sm
      }

      }
    

$peerjsoncreate=$svm_peer_create | ConvertTo-Json -Depth 4
  
  write-host $peerjsoncreate
 
  try{    
  
      write-host "Create new peer " -BackgroundColor blue    
      $response = Invoke-RestMethod -Uri $uri_peer_create -Headers $headjson -Credential $mycred -Method POST -body $peerjsoncreate  -ContentType "application/json" -ErrorAction Stop   
      write-host "SVM Peered : $($response.job)" -ForegroundColor green
   
   }
   catch
   {  
     write-host "Unable to create peering  " $_
   } 

   Start-Sleep -Seconds 15

########################################
########## Create SM relationship######
########################################

$svmname_sm=$svmname+ "_sm" 
$i=1
$maxcount=3
do{
      
      $flexVol_sm=$svmname_sm+ "_vol" + $i
      $flexVol_src=$svmname+ "_vol" + $i
    write-host "source volume $($flexvol_src)"
            
$uri_svmsm_create="https://$($clusterDRIP)/api/snapmirror/relationships" 
$src_path="$($svmname):$($flexvol_src)"
$dest_path= "$($svmname_sm):$($flexvol_sm)" 
$svm_sm_create=@{
     source= @{
    path=$src_path
    }
     destination= @{
    path=$dest_path
  }
 restore="false" 
 policy =@{name="MirrorAllSnapshots"}
}
$jsonsvmsmcreate=$svm_sm_create | ConvertTo-Json 
try{    
  
      write-host "Creating SnapMirror relationship for SM $($src_path) to $($dst_path)" -BackgroundColor blue    
      write-host $jsonsvmsmcreate
      write-host $uri_svmsm_create
      $response_sm = Invoke-RestMethod -Uri $uri_svmsm_create -Headers $headjson -Credential $mycred -Method POST -body $jsonsvmsmcreate  -ContentType "application/json" -ErrorAction Stop   
      write-host "SM relationship created completed : $($response_sm)" -ForegroundColor green
      start-sleep -Seconds 10
      $response_uuid = Invoke-RestMethod -Uri "$($uri_svmsm_create)?destination.path=$($dest_path)" -Headers  $headjson  -Credential $mycred -Method GET   -ContentType "application/json" -ErrorAction Stop   
      write-host "UUID for SM relationships with destination $($dest_path) is  $($response_uuid.records.uuid)"
         
      
#########################################
####Initialize the SM relationship #######
#########################################
      
      
      $sm_init=@{

      state = "snapmirrored"
      }
    start-sleep -Seconds 3
        

      $sm_init_json=$sm_init | ConvertTo-Json
      write-host $sm_init_json
      write-host "REST CAll .. $($uri_svmsm_create)/$($response_uuid.records.uuid)" -BackgroundColor blue 
      write-host "Start SnapMirror initialize.. " -BackgroundColor blue 
    $response_init = Invoke-RestMethod -Uri "$($uri_svmsm_create)/$($response_uuid.records.uuid)/" -Headers $headjson -Credential $mycred -Method PATCH -body $sm_init_json  -ContentType "application/json" -ErrorAction Stop   
      write-host "SM relationship initialized : $($response_init)" -ForegroundColor green

   }
   catch
   {  
     write-host "Unable to create SVM-S relationship " $_
   } 

   $i++

}while ( $i -le $maxcount)
  


