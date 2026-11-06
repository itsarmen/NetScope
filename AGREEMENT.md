# END-USER LICENSE AGREEMENT (EULA)

**NetScope — Network Monitor & Malicious Request Detector 2.0.0**
Copyright © 2026 itsarmen - <https://github.com/itsarmen>

> Plain-language summary (not a substitute for the terms below): the app is
> free and open source (MIT). It sends nothing anywhere - everything stays on
> your machine. Only capture traffic you are allowed to capture. The software
> comes with no warranty. By installing or using it, you accept these terms.

## 1. Acceptance

By downloading, installing, copying, or using the Software (the desktop
application, including documentation), you agree to be bound by this
Agreement. **If you do not agree, do not install or use the
Software - uninstall it and delete all copies.**

## 2. License grant and intended purpose

The Software's source code is licensed under the MIT License (see `LICENSE`).
In addition to those rights, you are granted a non-exclusive, non-transferable
right to install and use any number of copies of the provided builds on devices
you own or administer.

**Intended purpose:** this Software is a development and testing tool. It is
meant to be used while building and debugging **your own projects** - for
example inspecting the network traffic of a website or service you develop or
are explicitly authorized to test. Any use outside this purpose, and in
particular any harmful use (see §3), is prohibited. The Software is licensed,
not sold. All rights not expressly granted are reserved by the Author.

## 3. Scope of permitted use (important)

The license granted in §2 is limited strictly to the following scope:
development and testing of computer systems owned by you, or for which you
hold prior express authorization to conduct such development and testing.

Any use falling outside this scope is unlicensed, unauthorized, and strictly
prohibited. You warrant that every use you make of the Software falls within
the permitted scope and complies with all applicable laws and regulations in
every jurisdiction in which you use it.

You acknowledge that the Software is a technically capable instrument whose
operation outside the permitted scope may constitute a violation of law and
may expose you to civil and criminal liability. You assume sole and exclusive
responsibility for determining that each use is permitted, and you use the
Software entirely at your own risk (see §8).

## 4. User data and data protection

### 4.1. Local-first architecture

The Software is local-first by design:

- The application opens no listening network port and is not reachable from
  any network.
- Captured events - including connection metadata, DNS names and process
  attribution - are stored exclusively in a local SQLite database on your own
  device (`%LOCALAPPDATA%\NetScope\network.db`, or the equivalent path on
  other platforms).
- The Software creates no accounts and transmits no analytics, telemetry,
  crash reports, usage statistics, or any other data to the Author or to
  any third party, ever. There is no server side, no cloud backup, and no
  remote access of any kind.

### 4.2. Roles: you are the controller

Because the Author never receives, stores, or otherwise processes any data
captured with the Software, no controller-to-processor relationship exists
between you and the Author. There are no sub-processors, no data processing
addendum, and no international data transfers performed by the Software.

**You - the person operating the Software - act as the controller (within
the meaning of Article 4(7) of Regulation (EU) 2016/679, the General Data
Protection Regulation, "GDPR", and equivalent roles under other applicable
data protection laws) of every piece of personal data you capture, store,
export, or otherwise handle with the Software.** All obligations that data
protection law imposes on controllers rest with you alone.

### 4.3. Your duties as controller

Where your captured traffic contains personal data - which it ordinarily
will, since logins, tokens, cookies, contact forms, and analytics payloads
routinely do - you shall observe, at a minimum, the following principles
(cf. Article 5 GDPR):

- **Lawfulness, fairness and transparency.** Have a valid legal basis for
  every capture (see §3: your own or expressly authorized systems). Do not
  capture data relating to other persons without a basis.
- **Purpose limitation.** Capture only for the development and testing
  purpose stated in §2, and do not reuse captured data for incompatible
  purposes.
- **Data minimisation.** Capture as little as possible: keep the "skip
  static assets" filter enabled, narrow your browsing session to what the
  test requires, and prefer test accounts and synthetic data over real
  user data wherever feasible.
- **Accuracy.** Test data should be kept accurate and, where necessary,
  kept up to date.
- **Storage limitation.** Do not retain captured traffic longer than
  necessary for the testing purpose. Use the built-in Clear and Truncate
  functions to delete records, and note that uninstalling the Software
  deletes the local database (see §4.6).
- **Integrity and confidentiality.** Protect captured data against
  unauthorised or unlawful processing and against accidental loss,
  destruction, or damage (see §4.5).
- **Accountability.** You shall be able to demonstrate compliance with all
  of the above.

### 4.4. Sensitive material - heightened warning

Captured traffic may include passwords, session tokens, `Authorization`
headers, cookies, payment details, health-related information, or other
special categories of data (cf. Article 9 GDPR), whose processing is subject
to stricter conditions up to and including an outright prohibition. Exercise
extreme restraint: avoid capturing such material at all, and where
unavoidable, delete it immediately after the test. **Note: the Software
provides no masking, redaction, or anonymisation features - every captured
header and body is displayed and stored verbatim, exactly as transmitted**
(see §4.5).

### 4.5. Security of the local database

You expressly acknowledge and accept each of the following:

- The local database file is stored **unencrypted** on your device's
  filesystem. Anyone with access to your user account, your backups, or
  your disk can read every captured record in full, including credentials
  and tokens.
- You are responsible for device-level protections: operating-system user
  separation, full-disk encryption, screen locking, malware protection,
  and the secure handling of any exported JSON/XML files (which are
  likewise unencrypted).
- The Author has no ability to remotely wipe, recover, or protect your
  database, precisely because the Software transmits nothing (see §4.1).

### 4.6. Retention, erasure, and data-subject rights

If you capture personal data relating to other persons, you - as controller
- are responsible for honouring their rights, including the rights of access,
rectification, erasure, restriction, portability, and objection (cf.
Articles 12-22 GDPR). The Software assists you mechanically: records can be
inspected, exported, selectively deleted, truncated in bulk via the Truncate
function, and wiped entirely via Clear or by uninstalling the Software
(which deletes the database directory). Responding to data-subject requests
lawfully and on time remains your duty, not the Author's.

### 4.7. No transfers by the Software; your transfers are yours

The Software performs no cross-border or other transfers of personal data.
Any transfer you effect yourself - by exporting log files, sending them by
email, uploading them to issue trackers, or moving them to another machine
- is your own act as controller, subject in full to Chapter V GDPR (or
equivalent transfer rules), and your sole responsibility.

### 4.8. Confidentiality of communications

The interception of communications may additionally be governed by rules on
the confidentiality of electronic communications (in the EU, Article 5 of
Directive 2002/58/EC and its national implementations; elsewhere, equivalent
wiretapping and computer-misuse statutes). Nothing in this Agreement
authorizes interception beyond the permitted scope of §3.

### 4.9. Security standards alignment

The Software is developed with information-security best practice in mind,
aligned with the control objectives of **ISO/IEC 27001** (notably secure
system defaults, least privilege, and minimal attack surface: loopback-only
network binding, no inbound or outbound connections, no background services)
and the privacy principles of **ISO/IEC 27701** (data minimisation by
default, local-only processing). This statement describes development
principles only; it is not a claim of certification, and no certificate,
audit report, or statement of applicability is offered or implied.

### 4.10. Personal data breaches

Should personal data you captured be accidentally or unlawfully destroyed,
lost, altered, or disclosed (for example through device theft, malware, or
mishandled export files), any statutory breach-notification duties - including
notification to the supervisory authority and to affected data subjects
(cf. Articles 33-34 GDPR) - fall on you as controller. The Author, having no
access to your data, cannot detect, assess, or notify breaches on your behalf.

### 4.11. Records of processing

To the extent Article 30 GDPR (or an equivalent duty) obliges you to maintain
records of processing activities, you shall include your use of this Software
- its purposes, data categories, recipients (none, by design), retention
periods, and security measures - in those records yourself.

## 5. Restrictions

You agree not to: (a) use the Software for any unlawful purpose (see §3);
(b) remove or alter copyright notices, the LICENSE file, or the author header
comments in the source files; (c) misrepresent the origin of the Software or
present modified versions as the Author's work.

## 6. Open-source components

The Software incorporates third-party open-source components (including the
Flutter SDK, the Yaru theme, SQLite, and others), each governed by its own
license. Where those licenses conflict with this Agreement, the component
license prevails for that component.

## 7. No warranty

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT. CAPTURED DATA IS STORED
LOCALLY AT YOUR OWN RISK; KEEP YOUR OWN BACKUPS OF ANYTHING IMPORTANT.

## 8. Your responsibility - the Author is not responsible for anything

YOU USE THE SOFTWARE ENTIRELY AT YOUR OWN RISK. Everything you do with it -
what you capture, what you store, what you replay, and what consequences
follow - is **yours alone**. The Author is not responsible for anything:
not for your actions, not for your data, not for damage to you or anyone
else, whether caused by you, by a third party, or by the Software itself.

**Indemnity (hold harmless):** you agree to defend, indemnify, and hold
harmless the Author from and against any and all claims, damages, losses,
costs, and expenses (including reasonable legal fees) arising from or related
to your use or misuse of the Software - including, without limitation, any
unauthorized interception, data theft, surveillance, or other harmful or
unlawful use described in §3.

TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE AUTHOR SHALL NOT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR
ANY LOSS OF DATA, PROFITS, OR REVENUE, ARISING FROM THE USE OF OR INABILITY TO
USE THE SOFTWARE - INCLUDING ANY LIABILITY ARISING FROM UNLAWFUL INTERCEPTION
OR ANY OTHER HARM CARRIED OUT WITH THE SOFTWARE BY YOU OR ANY THIRD PARTY.
IF YOU DO NOT ACCEPT THIS, DO NOT USE THE SOFTWARE.

## 9. Termination

This Agreement is effective until terminated. It terminates automatically if
you breach any term. Upon termination you must uninstall the Software and
destroy all copies. Sections 3, 7, and 8 survive termination.

## 10. Respect

By using the Software you commit to the following principles of respect:

- **Respect for the law.** Observe the laws of the country you use the
  Software from, the laws of the European Union where applicable, and the
  applicable rules of international law. Where laws conflict, comply with
  the strictest applicable requirement.
- **Respect for other persons.** Respect the privacy, communications, and
  rights of others. Do not capture, store, or disclose traffic or data
  relating to any person without proper authorization and legal basis.
- **Respect for the work.** Respect the Author's work: keep copyright
  notices, the LICENSE file, and author attributions intact, and do not
  present the Software - or versions derived from it - as anyone else's
  work or as endorsed by anyone who has not endorsed it.

Breach of this section is a breach of this Agreement and terminates your
license under §9.

---

*This is a plain-language agreement template, not legal advice. For certified
legal certainty in your jurisdiction, have it reviewed by a lawyer.*
