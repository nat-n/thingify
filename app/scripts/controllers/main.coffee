'use strict'

angular.module('thingifyApp')

.controller 'MainCtrl', ($scope, thingifyHelper, $filter, $http, $window) ->
  # fetch the client id from the backend
  $http.get("/client_id").then (res) -> $scope.client_id = res.data

  # check for a code in the querystring
  codeMatch = /code=?([^&]*)/.exec(window.location.search.slice(1))
  $scope.code = codeMatch and codeMatch[1]

  # get access_token via the backend if we have a code
  if $scope.code
    auth_req = $http.get("/auth?code=#{$scope.code}")
    auth_req.then (res) ->
      $scope.token = /access_token=(.*?)&/.exec(res.data)
    auth_req.error ->
      alert('Uh oh: Authorization failed')

  $scope.files = []

  $scope.$watch 'input_files', (files) ->
    return unless files
    i = -1
    $scope.files = ({
                      name: f.name.split('.')[0]
                      size: f.size
                      i: i+=1
                      file: f
                      tv_obj: null
                      status: 'Selected'
                    } for f in files)

  $scope.thingify = (event, thing_data) ->
    if _.isString(thing_data.tags)
      thing_data.tags = thing_data.tags.split(/\s*,\s*/)

    # clear the files input element
    filesInput.value = []

    create = ((file, access_token) ->
      new_thing = _.cloneDeep(thing_data)
      new_thing.name = file.name
      file.status = 'Creating'

      thingifyHelper.create_thing(new_thing, access_token)
      .error ->
        # new thing creation failed
        file.status = 'Failed Creation'
      .then (res) ->
        # created new thing
        file.status = 'Created'
        file.tv_obj = res.data
        ru = thingifyHelper.request_upload(file, access_token)
        ru.then (res) ->
          file.status = 'Pre-registered Upload'
          # upload pre-registered successfully
          file.finalize_url = res.data.fields.success_action_redirect

          thingifyHelper.s3_upload(file, res.data)
          .error (res) ->
            # will always error, because of the success_action_redirect
            unless (res.xhr.status or res.xhr.response or res.xhr.responseType)
              # this means the error was due to a 303 which actually means success
              # Uploaded file successfully
              file.status = 'Uploaded'
            else
              # This looks like a real error
              file.status = 'Failed Upload'
              return

            fu = thingifyHelper.finalize_upload(file.finalize_url, access_token)
            fu.then (res) ->
              # upload finalized
              file.status = 'Upload Finalized'
            fu.error () ->
              # upload finalized
              file.status = 'Upload not finalised (don\'t worry)'

            file.status = "Finalizing Upload"

          file.status = "Uploading"

        ru.error () ->
          file.status = 'Upload Pre-registration failed'
    )

    fileIDs = _.range($scope.files.length)

    # maintain an activity pool of up to `active_max` things in progress
    active_max = 3
    count_active_things = () ->
      ($filter('thingStatus')($scope.files, 'inProgress')).length
    $scope.$watch (-> fileIDs.length and count_active_things()), (activity) ->
      if activity < active_max
        create($scope.files[fileIDs.shift()], $scope.token)


# bind multiple file upload input to a model
.directive 'filesModel', ($parse) ->
  restrict: 'A'
  link: (scope, element, attrs) ->
    model = $parse(attrs.filesModel)
    element.bind 'change', ->
      scope.$apply -> model.assign(scope, element[0].files)


.service 'thingifyHelper', ($http, $q) ->
  create_thing: (thing_data, access_token) ->
    $http
      method: 'post'
      url: 'http://api.thingiverse.com/things',
      headers:
        'Authorization': "Bearer #{access_token}"
      data: thing_data

  request_upload: (file, access_token) ->
    thing_id = file.tv_obj.id
    $http
      method: 'post'
      url: "http://api.thingiverse.com/things/#{thing_id}/files"
      headers:
        'Authorization': "Bearer #{access_token}"
      data:
        filename: file.file.name

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

    #
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


.filter 'thingStatus', ->
  result = []
  filter = (file, status) ->
    status is 'selected' and  file.status is 'Selected' or
    status is 'inProgress' and file.status in ['Creating', 'Created', 'Pre-registered Upload', 'Uploading', 'Uploaded', 'Finalizing Upload'] or
    status is 'completed' and file.status is 'Upload Finalized' or
    status is 'error' and file.status in ['Failed Creation', 'Failed Upload Pre-registration', 'Failed Upload', 'Upload not finalised (don\'t worry)']
  (files, status) ->
    result.length = 0
    result.push file for file in files when filter(file, status)
    result
