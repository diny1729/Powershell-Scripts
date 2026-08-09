<#
.SYNOPSIS
    Generates a web server SSL certificate signed by an existing Intermediate CA using OpenSSL.

.DESCRIPTION
    Creates an OpenSSL server configuration file with Subject Alternative Names (SANs), generates a private key 
    and Certificate Signing Request (CSR), signs the certificate using an existing Intermediate CA cert/key, 
    and bundles the resulting server certificate into a password-protected PFX file for IIS/web server binding.

.NOTES
    Prerequisites:
    - OpenSSL binary installed and accessible in the system environment PATH.
    - Valid existing Intermediate CA certificate and private key files.
#>

# Define the paths to your existing CA files here
$existingRootCert = "C:\Users\admin\Documents\Prod_Cert\root.crt"
$existingInterCert = "C:\Users\admin\Documents\Prod_Cert\intermediate.crt"
$existingInterKey  = "<REDACTED>"


# --- Configuration ---
$serverName = "<REDACTED>"
$dnsNames = @("*.myapp.com", "10.20.30.40")
$pfxPassword = "<REDACTED>"

	Write-Host "--- 1. Creating Server Configuration File ---" -ForegroundColor Cyan

	$sanList = $dnsNames | ForEach-Object { "DNS:$_" }
	$sanString = $sanList -join ","

	$serverConfig = @"
[ req ]
distinguished_name = req_distinguished_name
prompt = no
req_extensions = v3_req

[ req_distinguished_name ]
CN = $serverName

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $sanString
"@
	Set-Content -Path "server.cnf" -Value $serverConfig

	Write-Host "--- 2. Generating Server Key and CSR ---" -ForegroundColor Cyan
	# Generate new private key and Certificate Signing Request
	openssl req -new -nodes -keyout server.key -out server.csr -config server.cnf

	Write-Host "--- 3. Signing Server Cert with EXISTING Intermediate CA ---" -ForegroundColor Cyan
	# We use your existing intermediate.crt and intermediate.key
	openssl x509 -req -in server.csr `
		-CA $existingInterCert -CAkey $existingInterKey -CAcreateserial `
		-out server.crt -days 3650 -sha256 `
		-extfile server.cnf -extensions v3_req

	Write-Host "--- 4. Bundling PFX for IIS ---" -ForegroundColor Cyan
	# Bundle: Server Key + Server Cert + Intermediate Cert (the Chain)
	openssl pkcs12 -export -out "$serverName.pfx" `
		-inkey server.key -in server.crt -certfile $existingInterCert `
		-passout "pass:$pfxPassword"

	Write-Host "--- 5. Cleanup ---" -ForegroundColor Cyan
	Remove-Item server.cnf, server.csr, *.srl -ErrorAction SilentlyContinue

	Write-Host "------------------------------------------------" -ForegroundColor Green
	Write-Host "SUCCESS! $serverName.pfx created using existing CA." -ForegroundColor Green	



