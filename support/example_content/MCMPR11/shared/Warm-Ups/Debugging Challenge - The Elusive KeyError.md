---
title: Debugging Challenge - The Elusive KeyError
publish: true
created: __CREATED__
tags:
  - warmup
  - python
  - debugging
  - dictionaries
---

This code snippet is meant to look up the First Nation traditional name for a given BC community. However, when we run it for certain cities, it crashes with a `KeyError`.

Read the code below and try to spot the issue without running it.

```python
bc_communities = {
    "vancouver": "xʷməθkʷəy̓əm (Musqueam), Sḵwx̱wú7mesh (Squamish), and səlilwətaɬ (Tsleil-Waututh)",
    "victoria": "Lək̓ʷəŋən (Songhees and Esquimalt)",
    "kamloops": "Tk’emlúps te Secwépemc",
    "nanaimo": "Snuneymuxw"
}

def get_traditional_territory(city_name):
    # Standardize to title case
    city = city_name.title()
    
    # Return the territory info
    return bc_communities[city]

print(get_traditional_territory("Vancouver"))
```

What is causing the `KeyError`, and how would you fix it to handle missing cities gracefully?

> [!success]- Answer 1
> The dictionary keys are stored in all lowercase (`"vancouver"`, `"victoria"`), but the function standardizes the user's input to title case (`city = city_name.title()`), converting `"Vancouver"` to `"Vancouver"`. When it looks up `"Vancouver"` in the dictionary, it doesn't match the lowercase `"vancouver"`, resulting in a `KeyError`.
> 
> To fix this, we should standardize the input to lowercase using `.lower()` instead of `.title()`. Additionally, we should use the `.get()` method to avoid a crash if a city isn't in the dictionary at all.
> 
> ```python
> def get_traditional_territory(city_name):
>     city = city_name.lower()
>     return bc_communities.get(city, "Territory unknown")
> ```

%%curriculum-start%%
## Curriculum connection

![[K1.15]]

![[K1.4]]
%%curriculum-end%%
