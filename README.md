# Shibboleth SP Attribute Checker

When an Identity Provider (IdP) does not release all the SAML attributes required by a Service Provider (SP), the login fails without giving the user a clear explanation of what went wrong. This tool addresses that gap at the **Shibboleth SP level** (requires Shibboleth SP 3+), without requiring any changes to the protected application.

The solution consists of two files:

| File | Role |
|---|---|
| `attrChecker.html` | Error page template rendered by Shibboleth SP |
| `attrChecker.pl` | Perl script to auto-generate `attrChecker.html` from `attrChecker.orig.html` |


## Index

1. [How It Works](#how-it-works)
2. [Configuration (`shibboleth2.xml`)](#configuration-shibboleth2xml)
   1. [1. ApplicationDefaults](#1-applicationdefaults)
   2. [2. Sessions — AttributeChecker Handler](#2-sessions--attributechecker-handler)
   3. [3. ApplicationDefaults — Metadata AttributeExtractor](#3-applicationdefaults--metadata-attributeextractor)
   4. [4. Sessions — Errors Element](#4-sessions--errors-element)
   5. [5. Validate and Restart](#5-validate-and-restart)
3. [Error Page Template (`attrChecker.html`)](#error-page-template-attrcheckerhtml)
   1. [Fallback behavior for incomplete IdP metadata](#fallback-behavior-for-incomplete-idp-metadata)
   2. [Pixel tracking](#pixel-tracking)
   3. [Manual template customization](#manual-template-customization)
4. [Automation Script (`attrChecker.pl`)](#automation-script-attrcheckerpl)
   1. [File layout expected by the script](#file-layout-expected-by-the-script)
   2. [Setup](#setup)
     1. [1. Install the reference template (only once)](#1-install-the-reference-template-only-once)
     2. [2. Install the Perl script](#2-install-the-perl-script)
     3. [3. Make the Perl script executable](#3-make-the-perl-script-executable)
     4. [4. Enable Logging](#4-enable-logging)
   3. [Usage](#usage)
   4. [Typical workflow when changing required attributes](#typical-workflow-when-changing-required-attributes)
6. [Repository Structure](#repository-structure)

---

## How It Works

Shibboleth SP provides an `AttributeChecker` handler that validates a user session against a list of required attributes **before** completing the login. If one or more attributes are missing, the SP redirects the user to a configurable error template (`attrChecker.html`) instead of completing the login.

The template uses Shibboleth's `<shibmlp>` markup language to render dynamic content (SP entityID, IdP entityID, received/missing attributes) directly in the page. It also uses the `Metadata` `AttributeExtractor` to pull display name and contact information directly from the IdP's federation metadata, with graceful fallbacks for IdPs that do not publish `mdui:UIInfo` or contact elements.

[[TOP](#index)]

---

## Configuration (`shibboleth2.xml`)

### 1. ApplicationDefaults

Add `sessionHook` and `metadataAttributePrefix` to the `<ApplicationDefaults>` element:

```xml
<ApplicationDefaults entityID="https://<HOST>/shibboleth"
  REMOTE_USER="eppn persistent-id targeted-id"
  signing="front" encryption="false"
  sessionHook="/Shibboleth.sso/AttrChecker"
  metadataAttributePrefix="Meta-">
```

- `sessionHook`: activates the attribute check hook after authentication
- `metadataAttributePrefix="Meta-"`: prefixes all metadata-extracted attributes with `Meta-`, making them accessible in the template as `<shibmlp Meta-displayName />`, `<shibmlp Meta-Technical-Contact />`, etc.

[[TOP](#index)]

### 2. Sessions — AttributeChecker Handler

Add the `AttributeChecker` handler inside the `<Sessions>` element with the list of required attributes:

```xml
<Handler type="AttributeChecker"
         Location="/AttrChecker"
         template="attrChecker.html"
         attributes="eppn displayName cn sn givenName schacHomeOrganization schacHomeOrganizationType"
         flushSession="true"/>
```

For more complex scenarios, use `AND`/`OR` operators instead of the flat `attributes` list (note: `attrChecker.pl` only supports the flat `attributes` attribute):

```xml
<Handler type="AttributeChecker" Location="/AttrChecker" template="attrChecker.html" flushSession="true">
  <OR>
    <Rule require="displayName"/>
    <AND>
      <Rule require="givenName"/>
      <Rule require="sn"/>
    </AND>
  </OR>
</Handler>
```

[[TOP](#index)]

### 3. ApplicationDefaults — Metadata AttributeExtractor

Add the `AttributeExtractor` type `Metadata` alongside the existing `XML` type one. This allows the template to display useful info about the IdP from the federation metadata: display name, technical contact, Information URL, ...

```xml
<!-- Extracts display name and contact info for the authenticating IdP from federation metadata -->
<AttributeExtractor type="Metadata"
                    AttributeProfile="attributeProfile"
                    errorURL="errorURL"
                    DisplayName="displayName"
                    Description="description"
                    InformationURL="informationURL"
                    PrivacyStatementURL="privacyStatementURL"
                    OrganizationName="organizationName"
                    OrganizationDisplayName="organizationDisplayName"
                    OrganizationURL="organizationURL"
                    registrationAuthority="registrationAuthority">
  <ContactPerson id="Technical-Contact" contactType="technical" formatter="$EmailAddress"/>
  <Logo id="Small-Logo" height="16" width="16" formatter="$_string"/>
</AttributeExtractor>
```

> **Note:** `id="Technical-Contact"` combined with `metadataAttributePrefix="Meta-"` produces the attribute `Meta-Technical-Contact`, which is what `attrChecker.html` references. If you change the `id`, update the template accordingly.

[[TOP](#index)]

### 4. Sessions — Errors Element

Add or update the `<Errors>` element inside `<Sessions>` to include the `spEntityID` attribute pointing to the SP entityID. This ensures that the `<shibmlp spEntityID />` tag in the template is correctly populated with the SP entityID value:

`/etc/shibboleth/shibboleth2.xml` → `Sessions` element

```xml
<Errors session="sessionError.html"
        metadata="metadataError.html"
        access="accessError.html"
        ssl="sslError.html"
        localLogout="localLogout.html"
        logoutError="logoutError.html"
        globalLogout="globalLogout.html"
        spEntityID="https://<HOST>/shibboleth"/>
```

> **Note:** The `spEntityID` attribute drives the `<shibmlp spEntityID />` tag rendered in `attrChecker.html`. Without it, the SP entityID displayed in the error page and used in the pre-filled e-mail will be empty or incorrect. The `attrChecker.pl` script deliberately does not modify `<shibmlp spEntityID />` tags in the template, relying entirely on this configuration.

[[TOP](#index)]

### 5. Validate and Restart

```bash
sudo shibd -t && sudo systemctl restart shibd.service
```

[[TOP](#index)]

---

## Error Page Template (`attrChecker.html`)

[Attribute Checker template](./attrChecker.html)

The template renders a user-facing error page with:

- **Connection summary**: IdP display name (fallback to `entityID` if `mdui:UIInfo` is absent), SP entityID, timestamp, and IdP technical contact email
- **Attribute table**: all required attributes with missing ones highlighted in red
- **Pre-filled email**: a draft message addressed to the IdP administrator, ready to send via the user's mail client
- **"Report Problem" button**: opens the mail client with the pre-filled email (disabled automatically if the IdP metadata does not include a technical contact)

[[TOP](#index)]

### Fallback behavior for incomplete IdP metadata

The template handles IdPs that do not publish full metadata gracefully:

| Missing metadata element | Fallback behavior |
|---|---|
| `mdui:DisplayName` | Falls back to displaying the raw `entityID` |
| Technical contact email | "Report Problem" button is disabled; user is instructed to contact their institution's IT helpdesk directly |

[[TOP](#index)]

### Pixel tracking

The template includes a 1×1 transparent image used for server-side logging of failed logins:

```html
<!--PixelTracking-->
<img src="/track.png?idp=<shibmlp entityID/>&amp;miss=..." ... />
```

The `miss=` query string parameter encodes which attributes were missing using `<shibmlpifnot $attr>-$attr</shibmlpifnot>` tags, enabling log analysis per IdP and per missing attribute. Serve `track.png` from your web root and monitor the access log of the SP's web server.

Create your `track.png` into the DocumentRoot (adapt the redirect to your needs):
   
``` bash
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" | base64 -d > /var/www/html/$(hostname -f)/track.png
```

[[TOP](#index)]

### Manual template customization

If you add or remove required attributes, update three sections of the template manually (or use `attrChecker.pl` to automate this):

**1. Pixel tracking parameter** (after `miss=`, inside `<!--PixelTracking-->`):

```html
<shibmlpifnot $attr>-$attr</shibmlpifnot>
```

**2. Attribute table** (between `<!--TableStart-->` and `<!--TableEnd-->`):

```html
<tr <shibmlpifnot $attr> class='warning text-danger'</shibmlpifnot>>
  <th>$attr</th>
  <td><shibmlp $attr /></td>
</tr>
```

**3. Email body** (after `The attributes that were not released to the service are:`):

```html
 * <shibmlpifnot $attr>$attr</shibmlpifnot>
```

[[TOP](#index)]

---

## Automation Script (`attrChecker.pl`)

`attrChecker.pl` automates the manual customization steps above. It reads the required attributes directly from `shibboleth2.xml` and regenerates `attrChecker.html` from a reference template.

> **Limitation:** the script only supports the flat `attributes="..."` syntax in the `AttributeChecker` handler. It does **not** support `AND`/`OR` rule trees.

[[TOP](#index)]

### File layout expected by the script

| Path | Description |
|---|---|
| `/etc/shibboleth/shibboleth2.xml` | Shibboleth SP configuration (read-only) |
| `/etc/shibboleth/attrChecker.orig.html` | Reference template — **never modified by the script** |
| `/etc/shibboleth/attrChecker.html` | Generated output — **overwritten on each run** |

[[TOP](#index)]

### Setup

#### 1. Install the reference template (only once)

Copy the [Attribute Checker template](./attrChecker.html) in `/etc/shibboleth/attrChecker.orig.html`

#### 2. Install the Perl script

Copy the [Attribute Checker Perl script](./attrChecker.pl) in `/etc/shibboleth/attrChecker.pl`

#### 3. Make the Perl script executable

```bash
chmod +x /etc/shibboleth/attrChecker.pl
```

> **Important:** `attrChecker.orig.html` is the source of truth for the script. Apply any structural or cosmetic customizations to `attrChecker.orig.html`, **not** to `attrChecker.html`. The script will overwrite `attrChecker.html` on every run.

[[TOP](#index)]

#### 4. Enable Logging

Create your `track.png` into the DocumentRoot (adapt the redirect to your needs):
   
``` bash
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" | base64 -d > /var/www/html/$(hostname -f)/track.png
```

[[TOP](#index)]

### Usage

```bash
cd /etc/shibboleth
perl attrChecker.pl
```

The script will:

1. Parse `shibboleth2.xml` and extract the `attributes` list from the `AttributeChecker` handler
2. Load `attrChecker.orig.html` as the base template
3. Regenerate the three attribute-dependent sections:
   - pixel tracking `miss=` parameter
   - attribute table rows (between `<!--TableStart-->` and `<!--TableEnd-->`)
   - missing attribute list in the email body
4. Back up the existing `attrChecker.html` to `attrChecker.html.bak.<timestamp>`
5. Write the new `attrChecker.html`

Sample output:

```
Attributes from AttributeChecker: cn, displayName, eppn, givenName, schacHomeOrganization, schacHomeOrganizationType, sn
Backup of destination template saved to /etc/shibboleth/attrChecker.html.bak.1710000000

1) Generated template: /etc/shibboleth/attrChecker.html
2) Required attributes: cn, displayName, eppn, givenName, schacHomeOrganization, schacHomeOrganizationType, sn
3) Test: sudo shibd -t && sudo systemctl restart shibd.service
```

[[TOP](#index)]

### Typical workflow when changing required attributes

```bash
# 1. Edit shibboleth2.xml (update the attributes= list in the AttributeChecker handler)
sudo vim /etc/shibboleth/shibboleth2.xml

# 2. Regenerate attrChecker.html
sudo perl /etc/shibboleth/attrChecker.pl

# 3. Validate and restart
sudo shibd -t && sudo systemctl restart shibd.service

# 4. Check the SP Apache VirtualHost CustomLog:
193.206.129.66 - - [20/Sep/2018:15:05:07 +0000] "GET /track.png?idp=https://idp.example.org/idp/shibboleth&miss=-givenName-cn-sn-eppn-schacHomeOrganization-schacHomeOrganizationType HTTP/1.1" 200 472 "https://sp.example.org/Shibboleth.sso/AttrChecker?return=https%3A%2F%2Fsp.example.org%2FShibboleth.sso%2FSAML2%2FPOST%3Fhook%3D1%26target%3Dss%253Amem%253A43af2031f33c3f4b1d61019471537e5bc3fde8431992247b3b6fd93a14e9802d&target=https%3A%2F%2Fsp.example.org%2Fsecure" "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
```

The example shows that `idp.example.org` doesn't send `givenName`,`cn`,`sn`,`eppn`,`schacHomeOrganization`,`schacHomeOrganizationType` attributes.

[[TOP](#index)]

---

## Repository Structure

```
.
├── attrChecker.html   # Error page template (copy to /etc/shibboleth/)
└── attrChecker.pl     # Automation script (copy to /etc/shibboleth/)
```
[[TOP](#index)]
