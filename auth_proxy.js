#!/usr/bin/env node

/*
 * This little app gives some server side help to the Thingify app. The app's
 * client id and client secret are read from the app_credentials file in the
 * same directory and used to service two endpoints:
 *
 *   /client_id returns the client_id
 *
 *   /?code=... takes the provided code and swaps it for a auth_token from the
 *              thingiverse auth server.
 *
 */

'use strict'

var http = require('http');
var querystring = require('querystring');
var fs = require('fs');

var client_id, client_secret, portNumber,get_access_token, app_creds;


// setup
app_creds = fs.readFileSync(__dirname + "/app_credentials").toString().split('\n')
client_id = app_creds[0];
client_secret = app_creds[1];
portNumber = "9001";


// the server
http.createServer(function (req, res) {
  var codeMatch, code;

  codeMatch = /code=?([^&]*)/.exec(req.url.slice(2));

  if (codeMatch) {
    get_access_token(client_id, client_secret, codeMatch[1], function(auth_resp){
      console.log(client_id, client_secret, codeMatch[1], auth_resp)
      res.writeHead(200, {'Content-Type': 'application/json'});
      res.end(JSON.stringify(auth_resp))
    });
  } else if (req.url === '/client_id') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({client_id: client_id}))
  } else {
    res.writeHead(400)
    res.end('No');
  }

}).listen(portNumber);


get_access_token = function(client_id, client_secret, code, cb) {
  var post_data, req_options;

  post_data = querystring.stringify({
    client_id: client_id,
    client_secret: client_secret,
    code: code
  });

  req_options = {
      host: 'www.thingiverse.com',
      port: 80,
      path: '/login/oauth/access_token?'+post_data,
      method: 'POST'
  };

  http.request(req_options, function(resp) {
      resp.setEncoding('utf8');
      resp.on('data', function(result) { cb(result); });
  }).end();
};
