# Azure Active Directory SSO Setup Guide for Jenkins

This guide walks you through configuring Azure Active Directory (Azure AD) Single Sign-On (SSO) for your Jenkins instance running on EKS.

## Prerequisites

- Jenkins instance running with the `azure-ad` plugin installed
- Azure AD tenant with admin access
- Jenkins URL accessible (e.g., https://jenkins.yourdomain.com)

---

## Part 1: Azure AD Configuration

### Step 1: Register Application in Azure AD

1. **Login to Azure Portal**
   - Go to https://portal.azure.com
   - Navigate to **Azure Active Directory**

2. **Register New Application**
   - Click **App registrations** → **New registration**
   - Fill in the details:
     - **Name**: `Jenkins SSO` (or your preferred name)
     - **Supported account types**: 
       - Select "Accounts in this organizational directory only" (Single tenant)
     - **Redirect URI**: 
       - Platform: `Web`
       - URI: `https://jenkins.yourdomain.com/securityRealm/finishLogin`
         (Replace with your actual Jenkins URL)
   - Click **Register**

3. **Note Down Important Values**
   After registration, note these values (you'll need them later):
   - **Application (client) ID**: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
   - **Directory (tenant) ID**: `yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy`

### Step 2: Create Client Secret

1. In your app registration, go to **Certificates & secrets**
2. Click **New client secret**
   - **Description**: `Jenkins SSO Secret`
   - **Expires**: Choose appropriate expiration (e.g., 24 months)
3. Click **Add**
4. **IMPORTANT**: Copy the **Value** immediately (it won't be shown again)
   - Secret Value: `your-secret-value-here`

### Step 3: Configure API Permissions

1. Go to **API permissions** in your app registration
2. Click **Add a permission**
3. Select **Microsoft Graph**
4. Select **Delegated permissions**
5. Add these permissions:
   - `User.Read` (should be added by default)
   - `email`
   - `openid`
   - `profile`
6. Click **Add permissions**
7. Click **Grant admin consent for [Your Organization]** (requires admin)

### Step 4: Configure Token Configuration (Optional but Recommended)

1. Go to **Token configuration**
2. Click **Add optional claim**
3. Select **ID** token type
4. Add these claims:
   - `email`
   - `family_name`
   - `given_name`
   - `upn`
5. Click **Add**

---

## Part 2: Jenkins Configuration

### Option A: Using Kubernetes Secrets (Recommended for Production)

#### Step 1: Create Kubernetes Secret

Create a secret with your Azure AD credentials:

```bash
kubectl create secret generic jenkins-azure-ad \
  --from-literal=client-id='YOUR_CLIENT_ID' \
  --from-literal=client-secret='YOUR_CLIENT_SECRET' \
  --from-literal=tenant-id='YOUR_TENANT_ID' \
  -n jenkins
```

#### Step 2: Update values-eks-domain.yaml

Add the secret reference to your values file:

```yaml
controller:
  # Add to existing additionalExistingSecrets section
  additionalExistingSecrets:
    - name: jenkins-azure-ad
      keyName: client-id
    - name: jenkins-azure-ad
      keyName: client-secret
    - name: jenkins-azure-ad
      keyName: tenant-id
```

#### Step 3: Update JCasC Configuration

Replace the existing `securityRealm` and `authorizationStrategy` sections in your JCasC config:

```yaml
controller:
  JCasC:
    configScripts:
      jenkins-config: |
        jenkins:
          # ... existing jenkins config ...
          
          securityRealm:
            azureAd:
              clientId: "${jenkins-azure-ad-client-id}"
              clientSecret: "${jenkins-azure-ad-client-secret}"
              tenant: "${jenkins-azure-ad-tenant-id}"
              cacheDuration: 3600
          
          authorizationStrategy:
            globalMatrix:
              permissions:
                - "Overall/Administer:admin@yourdomain.com"
                - "Overall/Read:authenticated"
                - "Job/Build:authenticated"
                - "Job/Cancel:authenticated"
                - "Job/Read:authenticated"
                - "Job/Workspace:authenticated"
                - "Run/Replay:authenticated"
                - "Run/Update:authenticated"
                - "View/Read:authenticated"
```

### Option B: Using Direct Configuration (For Testing Only)

**WARNING**: This method exposes secrets in your values file. Use only for testing!

```yaml
controller:
  JCasC:
    configScripts:
      azure-ad-config: |
        jenkins:
          securityRealm:
            azureAd:
              clientId: "YOUR_CLIENT_ID"
              clientSecret: "YOUR_CLIENT_SECRET"
              tenant: "YOUR_TENANT_ID"
              cacheDuration: 3600
          
          authorizationStrategy:
            globalMatrix:
              permissions:
                - "Overall/Administer:admin@yourdomain.com"
                - "Overall/Read:authenticated"
```

---

## Part 3: Authorization Strategies

### Strategy 1: Global Matrix Authorization (Recommended)

Grant permissions based on Azure AD email addresses or groups:

```yaml
authorizationStrategy:
  globalMatrix:
    permissions:
      # Admin users (by email)
      - "Overall/Administer:admin@yourdomain.com"
      - "Overall/Administer:devops-lead@yourdomain.com"
      
      # All authenticated users
      - "Overall/Read:authenticated"
      - "Job/Build:authenticated"
      - "Job/Cancel:authenticated"
      - "Job/Read:authenticated"
      - "Job/Workspace:authenticated"
      - "Run/Replay:authenticated"
      - "Run/Update:authenticated"
      - "View/Read:authenticated"
```

### Strategy 2: Role-Based Authorization (Using Azure AD Groups)

First, configure Azure AD to send group claims:

**In Azure Portal:**
1. Go to your app registration → **Token configuration**
2. Add **Groups claim**
3. Select "Security groups" or "All groups"

**In Jenkins JCasC:**

```yaml
authorizationStrategy:
  globalMatrix:
    permissions:
      # Admin group (use Azure AD Group Object ID)
      - "Overall/Administer:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      
      # Developers group
      - "Overall/Read:yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
      - "Job/Build:yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
      - "Job/Read:yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
      
      # Viewers group
      - "Overall/Read:zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"
      - "Job/Read:zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"
```

### Strategy 3: Project-Based Authorization

For more granular control per job/folder:

```yaml
authorizationStrategy:
  projectMatrix:
    permissions:
      - "Overall/Administer:admin@yourdomain.com"
      - "Overall/Read:authenticated"
```

Then configure per-folder permissions in Jenkins UI or via JCasC folder configurations.

---

## Part 4: Complete Example Configuration

Here's a complete example to add to your `values-eks-domain.yaml`:

```yaml
controller:
  # Add Azure AD plugin
  installPlugins:
    - azure-ad
    # ... other plugins ...
  
  # Reference Azure AD secrets
  additionalExistingSecrets:
    - name: jenkins-azure-ad
      keyName: client-id
    - name: jenkins-azure-ad
      keyName: client-secret
    - name: jenkins-azure-ad
      keyName: tenant-id
  
  JCasC:
    configScripts:
      jenkins-config: |
        jenkins:
          systemMessage: "Production Jenkins - Azure AD SSO Enabled"
          # ... other jenkins config ...
        
        # Remove or comment out the old securityRealm and authorizationStrategy
        # securityRealm:
        #   local:
        #     allowsSignup: false
        
        # authorizationStrategy:
        #   loggedInUsersCanDoAnything:
        #     allowAnonymousRead: false
      
      azure-ad-security: |
        jenkins:
          securityRealm:
            azureAd:
              clientId: "${jenkins-azure-ad-client-id}"
              clientSecret: "${jenkins-azure-ad-client-secret}"
              tenant: "${jenkins-azure-ad-tenant-id}"
              cacheDuration: 3600
          
          authorizationStrategy:
            globalMatrix:
              permissions:
                # Replace with your admin email
                - "Overall/Administer:admin@yourdomain.com"
                - "Overall/Administer:devops@yourdomain.com"
                
                # Authenticated users permissions
                - "Overall/Read:authenticated"
                - "Job/Build:authenticated"
                - "Job/Cancel:authenticated"
                - "Job/Configure:authenticated"
                - "Job/Create:authenticated"
                - "Job/Delete:authenticated"
                - "Job/Discover:authenticated"
                - "Job/Move:authenticated"
                - "Job/Read:authenticated"
                - "Job/Workspace:authenticated"
                - "Run/Delete:authenticated"
                - "Run/Replay:authenticated"
                - "Run/Update:authenticated"
                - "View/Configure:authenticated"
                - "View/Create:authenticated"
                - "View/Delete:authenticated"
                - "View/Read:authenticated"
                - "SCM/Tag:authenticated"
```

---

## Part 5: Deployment Steps

### Step 1: Create the Kubernetes Secret

```bash
# Replace with your actual values
kubectl create secret generic jenkins-azure-ad \
  --from-literal=client-id='12345678-1234-1234-1234-123456789abc' \
  --from-literal=client-secret='your-secret-value-from-azure' \
  --from-literal=tenant-id='87654321-4321-4321-4321-cba987654321' \
  -n jenkins

# Verify the secret was created
kubectl get secret jenkins-azure-ad -n jenkins
```

### Step 2: Update Your Values File

Edit `values-eks-domain.yaml` and add the Azure AD configuration as shown above.

### Step 3: Upgrade Jenkins

```bash
helm upgrade --install jenkins . -f values-eks-domain.yaml -n jenkins
```

### Step 4: Wait for Jenkins to Restart

```bash
# Watch the pod restart
kubectl get pods -n jenkins -w

# Check logs if needed
kubectl logs -f jenkins-0 -c jenkins -n jenkins
```

### Step 5: Test SSO Login

1. Open your Jenkins URL: `https://jenkins.yourdomain.com`
2. You should see "Login with Azure" button
3. Click it and authenticate with your Azure AD credentials
4. You should be redirected back to Jenkins and logged in

---

## Part 6: Troubleshooting

### Issue 1: "Login with Azure" Button Not Appearing

**Solution:**
- Check if azure-ad plugin is installed: Go to **Manage Jenkins** → **Manage Plugins** → **Installed**
- Check Jenkins logs: `kubectl logs jenkins-0 -c jenkins -n jenkins | grep -i azure`
- Verify JCasC configuration was applied: **Manage Jenkins** → **Configuration as Code**

### Issue 2: Redirect URI Mismatch Error

**Error:** `AADSTS50011: The redirect URI specified in the request does not match`

**Solution:**
- Verify the redirect URI in Azure AD matches exactly: `https://jenkins.yourdomain.com/securityRealm/finishLogin`
- Check for trailing slashes
- Ensure HTTPS is configured correctly

### Issue 3: Invalid Client Secret

**Error:** `AADSTS7000215: Invalid client secret provided`

**Solution:**
- Verify the client secret in Kubernetes secret is correct
- Check if the secret has expired in Azure AD
- Recreate the secret in Azure AD and update Kubernetes secret

### Issue 4: User Has No Permissions After Login

**Solution:**
- Check the email address in authorizationStrategy matches the user's Azure AD email
- Verify the user authenticated successfully: Check Jenkins logs
- Add the user's email to the permissions list in JCasC config

### Issue 5: Cannot Access Jenkins After Enabling SSO

**Emergency Access:**

If you get locked out, you can temporarily disable security:

```bash
# Exec into Jenkins pod
kubectl exec -it jenkins-0 -n jenkins -- /bin/bash

# Disable security temporarily
cat > /var/jenkins_home/config.xml << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<hudson>
  <disabledAdministrativeMonitors/>
  <version>2.516.3</version>
  <numExecutors>0</numExecutors>
  <mode>NORMAL</mode>
  <useSecurity>false</useSecurity>
  <authorizationStrategy class="hudson.security.AuthorizationStrategy$Unsecured"/>
  <securityRealm class="hudson.security.SecurityRealm$None"/>
</hudson>
EOF

# Restart Jenkins
kubectl delete pod jenkins-0 -n jenkins
```

Then fix your configuration and re-enable security.

---

## Part 7: Advanced Configuration

### Enable Group-Based Authorization

**Step 1: Configure Azure AD to Send Groups**

In Azure Portal:
1. Go to your app registration → **Token configuration**
2. Click **Add groups claim**
3. Select **Security groups**
4. Check **Group ID** for ID tokens

**Step 2: Get Group Object IDs**

```bash
# Using Azure CLI
az ad group list --query "[].{Name:displayName, ObjectId:id}" -o table
```

**Step 3: Update JCasC Configuration**

```yaml
authorizationStrategy:
  globalMatrix:
    permissions:
      # Jenkins Admins Group (replace with your group Object ID)
      - "Overall/Administer:12345678-1234-1234-1234-123456789abc"
      
      # Jenkins Developers Group
      - "Overall/Read:23456789-2345-2345-2345-234567890bcd"
      - "Job/Build:23456789-2345-2345-2345-234567890bcd"
      - "Job/Read:23456789-2345-2345-2345-234567890bcd"
```

### Configure Session Timeout

```yaml
jenkins:
  securityRealm:
    azureAd:
      clientId: "${jenkins-azure-ad-client-id}"
      clientSecret: "${jenkins-azure-ad-client-secret}"
      tenant: "${jenkins-azure-ad-tenant-id}"
      cacheDuration: 3600  # Cache duration in seconds (1 hour)
```

### Enable Audit Logging

Add to your JCasC config:

```yaml
unclassified:
  auditTrail:
    loggers:
      - logFile:
          log: /var/jenkins_home/logs/audit.log
          limit: 10
          count: 5
```

---

## Part 8: Security Best Practices

1. **Use Kubernetes Secrets**: Never hardcode credentials in values files
2. **Rotate Secrets Regularly**: Set expiration on Azure AD client secrets
3. **Principle of Least Privilege**: Grant minimum required permissions
4. **Enable MFA**: Require multi-factor authentication in Azure AD
5. **Monitor Access**: Review Jenkins audit logs regularly
6. **Use Groups**: Manage permissions via Azure AD groups, not individual users
7. **Backup Configuration**: Keep backups of your JCasC configuration
8. **Test in Non-Prod**: Always test SSO changes in a non-production environment first

---

## Part 9: Verification Checklist

- [ ] Azure AD app registration created
- [ ] Client ID, Client Secret, and Tenant ID noted
- [ ] Redirect URI configured correctly in Azure AD
- [ ] API permissions granted and admin consent given
- [ ] Kubernetes secret created with Azure AD credentials
- [ ] azure-ad plugin added to installPlugins list
- [ ] JCasC configuration updated with Azure AD security realm
- [ ] Authorization strategy configured with admin users
- [ ] Helm upgrade completed successfully
- [ ] Jenkins pod restarted and running
- [ ] "Login with Azure" button appears on Jenkins login page
- [ ] Successfully logged in with Azure AD credentials
- [ ] User has appropriate permissions after login
- [ ] Tested with multiple users/groups

---

## Part 10: Rollback Plan

If SSO configuration fails, you can rollback:

```bash
# Rollback to previous Helm release
helm rollback jenkins -n jenkins

# Or restore previous values file
helm upgrade --install jenkins . -f values-eks-domain.yaml.backup -n jenkins
```

---

## Additional Resources

- **Azure AD Plugin Documentation**: https://plugins.jenkins.io/azure-ad/
- **Jenkins Configuration as Code**: https://github.com/jenkinsci/configuration-as-code-plugin
- **Azure AD App Registration**: https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app
- **Jenkins Security**: https://www.jenkins.io/doc/book/security/

---

## Support

If you encounter issues:
1. Check Jenkins logs: `kubectl logs jenkins-0 -c jenkins -n jenkins`
2. Review JCasC configuration: Jenkins UI → Manage Jenkins → Configuration as Code
3. Verify Azure AD configuration in Azure Portal
4. Check Kubernetes secrets: `kubectl describe secret jenkins-azure-ad -n jenkins`
