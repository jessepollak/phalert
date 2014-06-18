env = require 'node-env-file'
request = require 'request'
$ = require 'cheerio'
through = require 'through2'
Promise = require 'bluebird'
debug = require('debug')('')

env(__dirname + '/.env')
twilio = require('twilio')(process.env.TWILIO_ID, process.env.TWILIO_SECRET)

BASE_URL = 'http://www.producthunt.com'
domains = {
  'gethop.com': '2023745555'
}

getToday = ($body) ->
  posts = $body('.today .post')
  urls = posts.map (i, el) ->
    external: BASE_URL + $('.post-url', el)[0].attribs.href
    comments: BASE_URL + $('.view-discussion', el)[0].attribs.href

  urls.toArray().map (obj) ->
    new Promise (resolve, reject) ->
      request.head { uri: obj.external, timeout: 5000 }, (err, resp, body) ->
        if err
          console.log "ERROR: #{err}"
          return resolve null

        obj.external = resp.request.uri.href
        resolve obj

sendText = (result, domain, numbers) ->
  numbers = [numbers] if typeof(numbers) == "string"
  for number in numbers
    twilio.messages.create
      from: '+12407884901'
      to: number
      body: "Your domain #{domain} has been mentioned on Product Hunt.
            Read more here: #{result.comments}"
    , (err, message) ->
      console.log message

request.get BASE_URL, (err, resp, body) ->
  return console.log "ERROR: #{err}" if err

  $body = $.load body
  promises = getToday($body)
  Promise.all(promises).then (results) ->
    for domain, numbers of domains
      for result in results
        console.log domain, result?.external
        sendText(result, domain, numbers) if result?.external.match(domain)



