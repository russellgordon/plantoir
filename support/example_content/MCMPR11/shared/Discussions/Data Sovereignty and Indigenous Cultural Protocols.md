---
title: Data Sovereignty and Indigenous Cultural Protocols
publish: true
created: __CREATED__
tags:
  - discussion
  - data
  - ethics
  - indigenous
---

In the digital age, data is power. Historically, research and data collection regarding Indigenous peoples in Canada was extractive—conducted *on* communities rather than *with* or *by* them. This often led to misrepresentation, stigmatization, and the misuse of cultural knowledge.

**Data Sovereignty** is the right of a nation or group to govern the collection, ownership, and application of its own data.

### The OCAP® Principles

For First Nations in Canada, data sovereignty is guided by the **OCAP® principles** (established by the First Nations Information Governance Centre):

1. **Ownership:** A community owns information collectively, much like an individual owns their personal information.
2. **Control:** First Nations must control how information is collected, used, and disclosed.
3. **Access:** First Nations must have access to information and data about themselves and their communities.
4. **Possession:** Physical and jurisdictional control of the data servers and records must reside with First Nations.

### Software Design Implications

If you are a software developer building a platform for language revitalization (like FirstVoices) or a health tracking app for a local First Nation in BC, OCAP® radically changes how you design your database and cloud architecture.

- **Cloud Storage:** You cannot simply spin up an Amazon Web Services (AWS) server in the United States. US servers are subject to the US Patriot Act, meaning the US government could compel access to the data. Data must be hosted locally, preferably on servers owned by the Nation.
- **Access Control:** You cannot use standard "admin sees everything" database roles. Elders might dictate that specific stories or data points can only be accessed during certain seasons, or only by specific community members. The software must enforce these cultural protocols programmatically.

### Discussion Prompts

1. **The Tension with Open Data:** We often hear that "Data should be free and open." How does the concept of Open Data conflict with Indigenous Data Sovereignty? When is it harmful for data to be "open"?
2. **Designing for Protocols:** How would you design a database schema for an archive of traditional songs, where some songs can only be heard by family members, and others can only be played during the winter? What fields would you need to add to your data model?
3. **The Role of the Developer:** As a programmer working with community data, you are not just typing code; you are building the infrastructure that enforces rules. How can a developer ensure they are respecting OCAP® principles when hired by an external community?

### How we run this

We use a **talking circle** for this one — a protocol you may already
have used elsewhere at this school for group dialogue, and a fitting one
given the content.

- Desks or chairs move into a full circle; nobody sits at the front.
- One object — a stone, or something similarly plain kept for this
  purpose — is passed around the circle. Only the person holding it
  speaks. Everyone else listens, without interrupting, planning a
  rebuttal, or reacting.
- Passing without speaking is always allowed, and nobody follows up on it.
- The circle goes around at least twice: once to respond to the
  Discussion Prompts above generally, a second time to respond to
  something a classmate said in the first round.
- If your school has an Indigenous Education worker, Elder, or Knowledge
  Keeper in residence, this is a good discussion to invite them to open
  or sit in on — check with your teacher ahead of time.

%%curriculum-start%%
## Curriculum connection

![[D3.3]]

![[T1.4]]
%%curriculum-end%%
