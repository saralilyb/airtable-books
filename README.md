# airtable-books

by [jtth](https://jtth.net)

Update an Airbase base of books using the books' barcodes to look up the title, author, and cover image.

Held together using glue and baling wire.


         )))
        (((
      +-----+
      |     |]
      `-----'   
    ___________
    `---------'

Featuring the ol' hyperdev stack.

## Update an airtable base using books' barcodes

Define the following in ENV:

```
AWSID="xxx"
AWSSECRET="xxx"
AWSTAG="xxx-20"
AIRTABLEKEY="keyxxx"
AIRTABLEBASE="appxxx"
```

Then have a base set up like [this one](https://airtable.com/invite/l?inviteId=invWLlr6ELcvaLmMl&inviteToken=9465ed2b1ed60638b5557e88e84340fd50697b59cecc8b534a6505fd524e1c57). You can duplicate it.

Once everything's set up, use a mobile device to scan in some books. Don't worry about filling anything else in. Then go to the live page and click "update". Make sure you can see the base update in another window to ensure a feeling of wonder.

It's not super great at updating extant authors; this was all done kinda quickly.