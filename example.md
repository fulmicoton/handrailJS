url: "http://www.reddit.com/"
width: 1000
height: 800
output: "output.md"
---

Step 1

    check: ->
        true
    screenshot:
        selector: "#siteTable p.title a.title:first"
        filepath: "totot2b.png"
    action: ->
        @click '#siteTable a.title:first-of-type'
    debug: ->
        document.title 


Step 2

    check: ->
        true

