<#
.SYNOPSIS
    Generates a full 3-tier self-signed Certificate Authority (CA) hierarchy and server SSL certificate.

.DESCRIPTION
    Automates the generation of a complete 3-tier PKI infrastructure via OpenSSL:
    1. Root CA certificate and private key (10-year validity).
    2. Intermediate CA certificate signed by Root CA (10-year validity).
    3. Server certificate with Subject Alternative Names (SANs) signed by Intermediate CA.
    4. Bundles Server cert, key, and Intermediate cert into a password-protected PFX file for IIS.

.NOTES
    Prerequisites:
    - OpenSSL binary installed and accessible in the system environment PATH.
#>

# --- CONFIGURATION ---
$rootName = "MYAPP Root CA"
$interName = "MYAPP Intermediate CA"
$serverName = "<REDACTED>"
$dnsNames = @("*.myapp.com", "10.20.30.40")
$pfxPassword = "<REDACTED>"

# Ensure we are in the script's directory
Set-Location $PSScriptRoot

Write-Host "--- 1. Creating Configuration Files ---" -ForegroundColor Cyan

# 1. Create Root CA Config (Strictly for CA)
$rootConfig = @"
[ req ]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_ca

[ req_distinguished_name ]
CN = $rootName

[ v3_ca ]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
"@
Set-Content -Path "root.cnf" -Value $rootConfig

# 2. Create Intermediate CA Config
$interConfig = @"
[ req ]
distinguished_name = req_distinguished_name
prompt = no

[ req_distinguished_name ]
CN = $interName

[ v3_intermediate_ca ]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
"@
Set-Content -Path "intermediate.cnf" -Value $interConfig

# 3. Create Server Config (With SANs)
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
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $sanString
"@
Set-Content -Path "server.cnf" -Value $serverConfig


Write-Host "--- 2. Generating Root CA ---" -ForegroundColor Cyan
# Generate Root Key and Self-Signed Cert (10 years)
openssl req -x509 -new -nodes -days 3650 -sha256 -keyout root.key -out root.crt -config root.cnf


Write-Host "--- 3. Generating Intermediate CA ---" -ForegroundColor Cyan
# Generate Intermediate Key and CSR
openssl req -new -nodes -keyout intermediate.key -out intermediate.csr -config intermediate.cnf

# Sign Intermediate with Root CA (10 years)
openssl x509 -req -in intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial -out intermediate.crt -days 36500 -sha256 -extfile intermediate.cnf -extensions v3_intermediate_ca


Write-Host "--- 4. Generating Server Certificate ---" -ForegroundColor Cyan
# Generate Server Key and CSR
openssl req -new -nodes -keyout server.key -out server.csr -config server.cnf

# Sign Server Cert with Intermediate CA (825 days max for Chrome/macOS)
openssl x509 -req -in server.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -out server.crt -days 36500 -sha256 -extfile server.cnf -extensions v3_req


Write-Host "--- 5. Bundling PFX for IIS ---" -ForegroundColor Cyan
# Bundle Server Key + Server Cert + Intermediate Cert into one PFX
# We do NOT include the Root CA in the PFX chain usually, as that goes into the Client's Trust Store manually.
openssl pkcs12 -export -out "$serverName.pfx" -inkey server.key -in server.crt -certfile intermediate.crt -passout "pass:$pfxPassword"


Write-Host "--- 6. Cleanup ---" -ForegroundColor Cyan
# Remove temporary config and CSR files
Remove-Item *.cnf, *.csr, *.srl -ErrorAction SilentlyContinue

Write-Host "------------------------------------------------" -ForegroundColor Green
Write-Host "SUCCESS!" -ForegroundColor Green
Write-Host "Files Created:"
Write-Host "1. root.crt            -> Import to 'Trusted Root Certification Authorities' on Client & Server"
Write-Host "2. intermediate.crt    -> Import to 'Intermediate Certification Authorities' on Client & Server"
Write-Host "3. $serverName.pfx     -> Import to IIS (Password: $pfxPassword)"
Write-Host "------------------------------------------------"



