express = require 'express'
app = express()
coffeeMiddleware = require 'coffee-middleware'
engines = require 'consolidate'
bodyParser = require 'body-parser'
stylish = require 'stylish'
autoprefixer = require 'autoprefixer-stylus'

PORT = process.env.PORT

app.use(express.static('public'))

# sets up jade

app.set('view engine', 'pug')

# sets up coffeescript support

app.use coffeeMiddleware
  bare: true
  src: "public"
require('coffeescript/register')

app.use bodyParser.urlencoded
  extended: false
app.use bodyParser.json()
app.use bodyParser.text()

# sets up stylus and autoprefixer

app.use stylish
  src: __dirname + '/public'
  setup: (renderer) ->
    renderer.use autoprefixer()
  watchCallback: (error, filename) ->
    if error
      console.log error
    else
      console.log "#{filename} compiled to css"

app.listen PORT, ->
  console.log "Your app is running on #{PORT}"

# ROUTES

app.get '/', (request, response) ->
  response.render 'index.pug',
    title: 'airtable books'


app.get '/honk', (request, response) ->
  honk()
  response.render 'index.pug',
    title: 'we tried'

honk = () -> 
  # Go through the books base, and if there's no cover, add one from amazon.
  #   Requires a barcode, that gets converted from whatever it is, to
  #   library of congress.

  MAXRECORDS = 10000

  # for isbn conversion math, from NPM
  isbn = require 'isbn'

  # this code is from https://github.com/bcherny/isbn-cover/blob/master/isbn-cover.coffee

  url = (isbn) ->
    "http://images.amazon.com/images/P/#{isbn}"

  normalize = (isbn) ->
    # coerce to string
    isbn += ''
    # convert SBN to ISBN?
    if isbn.length is 9
      isbn = '0' + isbn
    length = isbn.length
    # check for length
    if length isnt 10 and length isnt 13
      throw new Error """
        isbn-cover expects ISBNs to be 10 or 13 characters long,
        passed "#{isbn}" (which is #{length} characters long)
      """
    isbn

  isbncover = (
    isbn,
    success = ->,
    error = ->
  ) ->
    uri = url normalize isbn
    # environment: browser
    if window?
      img = document.createElement 'img'
      img.src = uri
      img.onload = -> success img
      img.onerror = error
    # environment: node
    else
      request = require 'request'
      request uri, (err, res, img) ->
        if not err and res.statusCode is 200
          success img
        else
          error err

  # assumes barcode is somehow encoding isbn (10, 13, 9, whatever). Test on 9781781688373.
  getCoverURL = (barcode) ->
    url isbn.ISBN.parse(barcode).codes.isbn10


  #### Amazon part
  amazon = require 'amazon-product-api'
  client = amazon.createClient {
    awsId: process.env.AWSID,
    awsSecret: process.env.AWSSECRET,
    awsTag: process.env.AWSTAG
  }

  # just takes the first hit from amazon for the title
  getBookInfo = (isbn) ->
    client.itemLookup({
      idType: 'ISBN'
      itemId: isbn
      responseGroup: 'ItemAttributes'
    }).then((results) ->
      return results
    ).catch((err) ->
      console.error err
    )

  getBookTitle = (results) ->
    return results[0].ItemAttributes[0].Title[0]

  getAuthor = (results) ->
    return results[0].ItemAttributes[0].Author[0]

  #####################################################
  # Airtable part
  Airtable = require('airtable')

  configureAirtable = () ->
    baseParams = {
      endpointUrl: 'https://api.airtable.com'
      apiKey: process.env.AIRTABLEKEY
    }
    Airtable.configure(baseParams)
    return Airtable.base(process.env.AIRTABLEBASE)

  updateCoverForRecord = (id, coverUrl) ->
    base('Books').update(id, {
      "Cover Photo": [{
        "url": coverUrl
      }]
    }, (err, record) ->
      if err
        console.error err
        return
      return)

  updateNameForRecord = (id, name) ->
    base('Books').update(id, {
      "Name": name
    }, (err, record) ->
      if err
        console.error err
        return
      return)

  createAuthorForBookRecord = (bookRecordid, author) ->
    base('Authors').create({
      "Name": author,
      "Books": [bookRecordid]
    }, (err, record) ->
      if err
        console.error err
        return
      return)

  updateAuthorForBookRecord = (bookRecordid, author) ->
    authorRecord = getAuthorRecord author
    #existingBooks = base('Authors').find(authorRecord.id)
    id = authorRecord.id
    books = authorRecord.fields.Books
    books.push(bookRecordid)
    base('Authors').update(id, {
      "Name": author,
      "Books": books
    }, (err, record) ->
      if err
        console.error err
        return
      return)


  authorsList = []
  gatherAuthors = (base) ->
    base('Authors').select({
      maxRecords: MAXRECORDS
      view: 'Main View'
      }).eachPage ((records, fetchNextPage) ->
      # This function (`page`) will get called for each page of records.
      records.forEach (record) ->
        authorsList.push record._rawJson
        # console.log record
        return
      fetchNextPage()
      return
    ), (err) ->
      if err
        console.error err
        return
      return

  doesAuthorExist = (author) ->
    console.log 'list', JSON.stringify authorsList
    return authorsList.some( (record) -> record.fields.Name == author )

  getAuthorRecord = (author) ->
    return authorsList.find( (record) -> record.fields.Name == author )

  peruseBooks = (base) ->
    gatherAuthors(base)
    base('Books').select({
      maxRecords: MAXRECORDS
      view: 'Main View'
      }).eachPage ((records, fetchNextPage) ->
      # This function (`page`) will get called for each page of records.
      records.forEach (record) ->
        barcode = await record.get('Barcode')
        console.log record.id, 'id', barcode, 'barcode'
        # console.log 'book info: \n', JSON.stringify bookInfo
        if (not await record.get('Cover Photo')) && barcode
          console.log record.id, 'did not have a cover but has barcode', barcode.text
          coverUrl = getCoverURL barcode.text
          console.log '  replacing it with', coverUrl
          updateCoverForRecord(record.id, coverUrl)
        if (not await record.get('Name')) && barcode
          console.log record.id, 'did not have name entry but has barcode', barcode.text
          bookInfo = await getBookInfo barcode.text
          title = await getBookTitle bookInfo
          console.log '  replacing it with', title
          updateNameForRecord(record.id, title)
        if (not await record.get('Author') && barcode)
          console.log record.id, 'did not have author entry but has barcode', barcode.text
          bookInfo = if bookInfo then bookInfo else await getBookInfo barcode.text
          author = await getAuthor bookInfo
          # check if the author exists
          doesAuthorExistBool = doesAuthorExist author
          console.log record.id, 'with author', author, 'doesAuthorExistBool', doesAuthorExistBool
          if doesAuthorExistBool
            console.log 'updating author record for author', author
            updateAuthorForBookRecord(record.id, author)
          else
            console.log 'creating author record for author', author
            createAuthorForBookRecord(record.id, author)

        return
      # To fetch the next page of records, call `fetchNextPage`.
      # If there are more records, `page` will get called again.
      # If there are no more records, `done` will get called.
      fetchNextPage()
      return
    ), (err) ->
      if err
        console.error err
        return
      return

  base = configureAirtable()
  peruseBooks(base)

