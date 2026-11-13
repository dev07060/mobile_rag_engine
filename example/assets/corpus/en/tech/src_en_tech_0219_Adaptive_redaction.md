# Adaptive redaction

- source_key: src_en_tech_0219
- language: en
- domain: tech
- length_bucket: short
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Adaptive_redaction

---

Adaptive redaction is a form of redaction whereby sensitive parts of a document are automatically removed based on policy. It is primarily used in next generation Data Loss Prevention (DLP) solutions.

Content and context
The policy is a set of rules based on content and context. Context can include:

Who is sending (or uploading) the information.
Who is receiving the information (including a website if uploading or downloading).
The communication channel (e.g. email, web, copy to removable media).
The content can be 'visible' information, such as that you see on the screen. For example, sending unprotected credit card information outside an organisation breaches the Payment Card Industry Data Security Standard (PCI DSS regulations). Many organisations accept credit card information through incoming email, but a reply to an email containing such information would send out the prohibited information. That would cause a breach of policy. Adaptive redaction can therefore be used to remove just the credit card number but allow the email to be sent.
Content can also be 'invisible' information such as that in document properties and revision history, and it can also be 'active' content which has been embedded in an electronic document, such as a macro. Release of 'invisible' information has on several occasions created embarrassment for government bodies.

Purpose
Adaptive redaction is designed to alleviate "False Positive" events created with Data loss prevention software (DLP) security solutions. False positives occur when a DLP policy triggers and prevents legitimate outgoing communication. In the majority of cases this is caused through oversight by the sender.

See also
Data masking
Redaction
Tokenization (data security)

References
