'use strict'

angular.module('thingifyApp')

.service 'thingiverseAPI', ($http, $q) ->
  api_host = 'http://api.thingiverse.com'
  create_thing: (thing_data, access_token) ->
    $http
      method: 'post'
      url: "#{api_host}/things",
      headers:
        'Authorization': "Bearer #{access_token}"
      data: thing_data

  request_upload: (file, access_token) ->
    thing_id = file.tv_obj.id
    $http
      method: 'post'
      url: "#{api_host}/things/#{thing_id}/files"
      headers:
        'Authorization': "Bearer #{access_token}"
      data:
        filename: file.file_name

  s3_upload: (file, instructions) ->
    action = instructions.action
    fields = instructions.fields

    # build formdata object
    fd = new FormData()
    fd.append('AWSAccessKeyId', fields.AWSAccessKeyId)
    fd.append('Content-Disposition', fields['Content-Disposition'])
    fd.append('Content-Type', fields['Content-Type'])
    fd.append('acl', fields.acl)
    fd.append('bucket', fields.bucket)
    fd.append('key', fields.key)
    fd.append('policy', fields.policy)
    fd.append('signature', fields.signature)
    fd.append('success_action_redirect', fields.success_action_redirect)
    file.file['Content-Type'] = fields['Content-Type']
    fd.append('file', file.file)

    # make request and return as promise
    deferred = $q.defer()
    deferred.promise.error = deferred.promise.catch
    xhr = new XMLHttpRequest()
    xhr.open 'POST', action
    xhr.send(fd)
    xhr.onreadystatechange = (e) ->
      if xhr.readyState == 4
        r =
          data: xhr.response
          status: xhr.status
          headers: xhr.getResponseHeader
          config: {}
          xhr: xhr
        if r.status is 200
          deferred.resolve(r)
        else
          deferred.reject(r)
    deferred.promise

  finalize_upload: (finalize_url, access_token) ->
    $http.post finalize_url+ "?access_token=#{access_token}"

  publish_thing: (thing_id, access_token) ->
    $http
      method: 'post'
      url: "#{api_host}/things/#{thing_id}/publish"
      headers:
        'Authorization': "Bearer #{access_token}"

  delete_thing: (thing_id, access_token) ->
    $http
      method: 'delete'
      url: "#{api_host}/things/#{thing_id}"
      headers:
        'Authorization': "Bearer #{access_token}"

  collections_by_user: (access_token) ->
    $http.get("#{api_host}/users/me/collections?access_token=#{access_token}")

  add_thing_to_collection: (collection_id, thing_id, access_token) ->
    $http
      method: 'post'
      url: "#{api_host}/collections/#{collection_id}/thing/#{thing_id}"
      headers:
        'Authorization': "Bearer #{access_token}"
