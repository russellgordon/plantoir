---
id: videos
checked: 2.0.0
covers:
- support/quartz/plugins/transformers/plantoirVideo.ts
- support/quartz/plugins/transformers/videoRules.js
- support/quartz/components/styles/videos.scss
- support/agent_guidance/skills/plantoir-page-authoring/SKILL.md
- contracts/shared-rules.json
keywords:
- video
- videos
- film
- clip
- YouTube
- You Tube
- Vimeo
- embed
- embed a video
- player
- unlisted
- Shorts
- playlist
- start time
- youtube-nocookie
- video blocked at school
- video will not play
description: A page shows a YouTube or Vimeo video when its address is written in the form used for a picture.
---
A page can show a video from YouTube or Vimeo. You write the video's address in the form used for a picture. Students see a player there on the class website.

## Steps

1. On YouTube or Vimeo, open the video and press its Share button. Copy the address it gives.
2. In Obsidian, open the page. On a line of its own, type the picture form. It is an exclamation mark, then words in square brackets that say what the video is, then the address in round brackets.

```text wrap
![Mitosis in three minutes](https://vimeo.com/76979871)
```

{{picture:videos-1}}
alt: A page in Obsidian with a video's address on a line of its own, in the form used for a picture.

3. In Plantoir, preview the section. The player is on the page where the line is.

{{picture:videos-2}}
alt: The same page on the class website, with the video's player where the line was.

4. Publish the page if it is not published yet. Students see the video after the section is next deployed.

## The words in the brackets

The words in the square brackets become the player's title. A student who uses a screen reader hears them, so say what the video is. With nothing in the brackets, the title is {{say:shared-rules#videoEmbeds.titles.youtube}} or {{say:shared-rules#videoEmbeds.titles.vimeo}}, which tells that student nothing about it.

## The addresses that work

- **YouTube**: the address from the Share button, the address from the browser's address bar, a Short, and a playlist. A start time in the address is kept, so the video begins there.
- **Vimeo**: the address of one video. For an unlisted video, use the address the Share button gives. It has a second part after the video's number, and the video plays only with that part.

The code a video site gives for embedding its player still works when pasted into a page. Plantoir leaves that code exactly as it is.

## What students see

- **A player in the page.** It is at most 600 pixels wide, in the shape of a wide screen, and narrower on a phone.
- **The video is not copied into the website.** It plays from YouTube or Vimeo, so a student needs an internet connection. A printed page does not show it.
- **A player loads as the student scrolls near it**, not all at once when the page opens. The video starts when the student presses play.

## Privacy

- YouTube players come from youtube-nocookie.com, the address YouTube gives for its privacy-enhanced mode.
- Vimeo players are asked not to track the viewer.

## If it does not work

- **A YouTube video plays at home and not at school.** The school's network may allow youtube.com and block youtube-nocookie.com. Ask the people who run the network to allow both.
- **The page shows a broken picture where the video should be.** The address is not the address of one video. A Vimeo showcase or profile is not, and neither is the address of a YouTube live stream. Use the address the video's Share button gives.
- **You pasted the address from your own browser after uploading a video to Vimeo.** That address is for managing the video, and the page shows a broken picture. Open the video's Share button at Vimeo and use the address it gives.
- **A Vimeo video does not play on the class website.** Its owner may have limited it to certain websites. It then plays only on the websites the owner has listed at Vimeo, and your class website must be one of them.
- **In Obsidian a Vimeo line looks like a picture that did not load.** Obsidian does not show a Vimeo address in this form as a player. The class website does.
- **The video is a file of your own.** That is a different thing. It goes in the course's Media folder: see [Pictures, PDFs and the Media folder](page:media).
