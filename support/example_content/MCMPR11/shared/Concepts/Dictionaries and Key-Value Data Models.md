---
title: "Dictionaries and Key-Value Data Models"
publish: true
created: __CREATED__
tags:
  - concept
  - data-structures
enableToc: true
---
> [!abstract] At a glance
> Dictionaries associate unique keys with values using hash tables, providing instantaneous $O(1)$ lookup times. We explore nested data modeling, inverted indexing, and frequency counting across BC environmental and linguistic datasets.

## The Power of Associative Mappings

While lists store elements in an ordered sequence indexed by integers ($0, 1, 2, \dots$), dictionaries map descriptive keys directly to values.

### Modeling a BC Ferry Terminal Status Record

```python
terminal_status = {
    "terminal_code": "TSA",
    "name": "Tsawwassen Ferry Terminal",
    "region": "Metro Vancouver",
    "active_routes": ["Swartz Bay", "Duke Point", "Southern Gulf Islands"],
    "current_weather": {
        "wind_speed_knots": 28.5,
        "visibility_nm": 4.2,
        "gale_warning": True
    },
    "sailings_delayed": 2
}

# Direct dictionary lookup
if terminal_status["current_weather"]["gale_warning"]:
    print(f"Advisory for {terminal_status['name']}: Sailings subject to weather delays.")
```

---

## Building an Inverted Search Index

An **inverted index** maps search keywords back to the primary record IDs that contain them. This is the algorithmic foundation of search engines and language platforms like **FirstVoices**:

```python
# Lexicon database of Coast Salish marine terms
lexicon = {
    "W-101": {"term": "sqi't", "gloss": "sea lion", "tags": ["marine", "mammal", "wildlife"]},
    "W-102": {"term": "stqe:ye", "gloss": "wolf", "tags": ["land", "mammal", "predator"]},
    "W-103": {"term": "s-ts'i'tkwum", "gloss": "killer whale / orca", "tags": ["marine", "mammal", "sacred"]}
}

def build_tag_index(dataset: dict) -> dict:
    """Construct an inverted index mapping each tag to a list of word IDs."""
    index = {}
    for word_id, entry in dataset.items():
        for tag in entry["tags"]:
            if tag not in index:
                index[tag] = []
            index[tag].append(word_id)
    return index

# Querying all marine terms in O(1) time
tag_index = build_tag_index(lexicon)
marine_word_ids = tag_index.get("marine", [])
print(f"Marine records: {[lexicon[wid]['term'] for wid in marine_word_ids]}")
# Output: Marine records: ["sqi't", "s-ts'i'tkwum"]
```

%%curriculum-start%%
## Curriculum connection

![[K1.4]]

![[K1.16]]
%%curriculum-end%%
