# Approved Publication Arrangement

- source_key: src_en_finance_0213
- language: en
- domain: finance
- length_bucket: short
- collected_at: 2026-02-22
- url: https://en.wikipedia.org/wiki/Approved_Publication_Arrangement

---

An Approved Publication Arrangement (APA) is an entity authorized under the MiFID II directive to publish trade reports on behalf of investment firms, fulfilling requirements outlined in Article (4)(1)(52) in the European Union. These reports contribute to increased transparency in over-the-counter (OTC) markets by disseminating both pre-trade quotes and post-trade transaction data. The MiFID II directive, which came into force in January 2018, mandates the use of APAs to enhance transparency in OTC markets.
While the term APA technically refers to the organization itself, it is also commonly used to refer to the data they publish.

History
APAs, Approved Reporting Mechanisms and Consolidated Tape Providers were new categories of Data Reporting Services Providers (DRSPs) that were introduced as part of MiFID II in Europe in 2014 that had not existed under MiFID I.
For the APA data it is distinguished into three asset classes: bonds, derivatives of all kind (interest rate/Credit/FX/Commodity/Equity), and Structured Finance. 

Data structure
Each APA data record contains information such as:

Agreement Time and Date in the variable TRADING_DATE_AND_TIME in ISO 8601 format, e.g. 2019-08-08T03:14:15.926000+00:00
Publication Time
ISIN to uniquely identify the financial instrument (if INSTRUMENT_ID_TYPE is set to ISIN), for instance INSTRUMENT_ID=HU0000403118 refers to a government bond of Hungary with maturity date 2027-10-27.
Name of the financial instrument
Price (and currency)
Volume
Trade type (INSTRUMENT_ID_TYPE)

Example
A (shortened) example record in JSON format looks like this:

See also
Request for quote
Legal Entity Identifier (LEI)
International Securities Identification Number (ISIN)
Markets in Financial Instruments Directive 2014 (MiFID II)

References

External links
A concise summary on the topic, understandable for laymen
