fetch = require 'isomorphic-fetch'
log = require './log'
shell = require('electron').shell;
JobSelectorView = require './job-selector-view'
PipelineSelectorView = require './pipeline-selector-view'
AllPipelineSelectorView = require './all-pipeline-selector-view'

class GitlabStatus
  constructor: (@view, @timeout=null, @projects={}, @pending=[], @jobs={}, @allPipelines={}) ->
    @token = atom.config.get('gitlab-integration.token')
    @artifactReportPath = atom.config.get('gitlab-integration.artifactReportPath')
    @period = atom.config.get('gitlab-integration.period')
    @updating = {}
    @watchTimeout = null
    @view.setController(@)

  fetch: (host, q, paging=false) ->
    @load(host,q).then((res) =>
      log " <- ", res
      if res.headers.get('X-Next-Page')
        if paging
          log " -> retrieving #{res.headers.get('X-Total-Pages')} pages"
          Promise.all(
            [res.json()].concat(
              new Array(
                parseInt(res.headers.get('X-Total-Pages')) - 1,
              ).fill(0).map(
                (dum, i) =>
                  log " -> page #{i + 2}"
                  fetch(
                    "https://#{host}/api/v4/#{q}" +
                    (if q.includes('?') then '&' else '?') +
                    "per_page=" + res.headers.get('X-Per-Page') +
                    "&page=#{i+2}", {
                      headers: {
                        'PRIVATE-TOKEN': @token
                      }
                    }
                  ).then((page) =>
                    log "     <- page #{i + 2}", page
                    page.json()
                  ).catch((error) =>
                    console.error "cannot fetch page #{i + 2}", error
                    Promise.resolve([])
                  )
              )
            )
          ).then((all) =>
            Promise.resolve(all.reduce(
              (all, one) =>
                all.concat(one)
              , [])
            )
          )
        else
          log " -> ignoring paged output for #{q}"
          res.json()
      else
        res.json()
    )
    .then( (result) =>
      if result?.error
        throw result
      else
        return result
    )

  load: (host, q) ->
    log " -> fetch '#{q}' from '#{host}"
    fetch(
      "https://#{host}/api/v4/#{q}", {
        headers: {
          "PRIVATE-TOKEN": @token,
        }
      }
    )

  watch: (host, projectPath, repos) ->
    projectPath = projectPath.toLowerCase()
    if not @projects[projectPath]? and not @updating[projectPath]?
      @updating[projectPath] = false
      @view.loading projectPath, "loading project..."
      @fetch(host, "projects?membership=yes", true)
      .then( (projects) =>
        log "received projects from #{host}", projects
        if projects?
          project = projects.filter(
            (project) =>
              project.path_with_namespace.toLowerCase() is
                projectPath
          )[0]
          if project?
            @projects[projectPath] = { host, project, repos }
            @update()
          else
            @view.unknown(projectPath)
        else
          @view.unknown(projectPath)
      ).catch((error) =>
        if error.error_description
          atom.notifications.addWarning(
            "Gitlab-Integration: #{error.error}: #{error.error_description}",
            {dismissable: true}
          )
        console.error "cannot fetch projects from #{host}", error
        @updating[projectPath] = undefined
        @view.unknown(projectPath)
      )

  printHeader: (job) ->
    "[0K[32;1m Log from branch #{job.ref} | job  #{job.name} | #  #{job.id} | pipeline  #{job.pipeline.id} [0;m"

  loadJob: (host, project, job) ->
    atom.notifications.addInfo(
      "Downloading build log for job #{job.name} #{job.id}",
      {dismissable: true}
    )
    @load(host, "projects/#{project.id}/jobs/#{job.id}/trace", false)
      .then( (res) ->
        return res.text()
      )
      .then( (text) ->
        return text: text, job: job
      )
      .catch((error) ->
        atom.notifications.addWarning(
          "Unable to load the build log due to #{error}",
          {dismissable: true}
        )
        console.error "cannot fetch the build log from projects/#{project.id}/jobs/#{job.id}/trace", error
      )

  openLog: (projectPath, job) ->
    { host, project, repos } = @projects[projectPath]
    @loadJob(host, project, job)
    .then( (downloadedLog) =>
      atom.workspace.open(undefined, {
        # split : 'right'
        }).then (editor) =>
          # editor.setFileName("#{job.name}.#{job.ref}.#{job.id}")
          editor.setGrammar(atom.grammars.grammarForScopeName('text.ansi'))
          editor.insertText @printHeader downloadedLog.job
          editor.insertNewline()
          editor.insertNewline()
          editor.insertText(downloadedLog.text)
    )
    .catch((error) ->
      console.error "cannot open editor for the build log of #{projectPath} and job #{job.id}", error
    )

  openFailedLogs: (projectPath, jobs) ->
    @openLogs(projectPath, jobs.filter (job) -> job.status is 'failed')

  openFailedLogsInGroup: (projectPath, jobs, mainJob) ->
    @openFailedLogs(projectPath, jobs.filter (job) -> job.name is mainJob.name)

  openLogs: (projectPath, jobs) ->
    { host, project, repos } = @projects[projectPath]

    atom.notifications.addInfo(
      "Downloading build logs for #{jobs.length} jobs",
      {dismissable: true}
    )

    jobsToLoad = (
      @loadJob(host, project, aJob) for aJob in jobs
    )

    Promise.all(jobsToLoad)
    .then (logs) =>
      logs?.sort (a, b) ->
        return -1 if a.job.name < b.job.name
        return 1 if a.job.name > b.job.name

        return -1 if a.job.id < b.job.id
        return 1 if a.job.id > b.job.id
        return 0

      atom.workspace.open(undefined, {
        # split : 'right'
        }).then (editor) =>
          # editor.setFileName("#{job.name}.#{job.ref}.#{job.id}")
          editor.setGrammar(atom.grammars.grammarForScopeName('text.ansi'))
          for l in logs
            editor.insertNewline()
            editor.insertText @printHeader l.job
            editor.insertNewline()
            editor.insertText(l.text)
            # atom.notifications.addInfo(
            #     "Build log #{l.job.name} (#{l.job.id}) downloaded",
            #     {dismissable: true}
            # )
      .catch((error) ->
        console.error "cannot open editor for build logs of jobs of #{projectPath}", error
      )

  openReport: (projectPath, job) ->
    if not job.artifacts_file
      atom.notifications.addWarning(
        "No artifacts for job #{job.name}",
        {dismissable: true}
      )
      return

    path = @artifactReportPath.split('<JOB_NAME>').join(job.name)

    if not path
      atom.notifications.addWarning(
        "Unknown path for artifact to download for #{job.name}",
        {dismissable: true}
      )
      return

    { host, project, repos } = @projects[projectPath]
    shell.openExternal("https://#{host}/#{encodeURI(projectPath)}/-/jobs/#{job.id}/artifacts/raw/#{path}");

  openGitlabCICD: (projectPath) ->
    { host, project, repos } = @projects[projectPath]
    return unless host
    shell.openExternal("https://#{host}/#{projectPath}/pipelines");

  openPipeline: (projectPath, stages) ->
    if stages
      { host, project, repos } = @projects[projectPath]
      shell.openExternal("https://#{host}/#{projectPath}/pipelines/#{stages[0].pipeline}");
    else
      @openGitlabCICD(projectPath)

  openJobSelector: (projectPath, stage) ->
    @activeSelector = new JobSelectorView(stage.jobs, @ , projectPath)

  openPipelineSelector: (projectPath) ->
    { host, project, repos } = @projects[projectPath]
    @activeSelector = new PipelineSelectorView(project.pipelines, @ , projectPath)

  openAllPipelineSelector: (projectPath) ->
    pipelines = @allPipelines[projectPath]
    if pipelines?.length > 0
      @activeSelector = new AllPipelineSelectorView(pipelines, @ , projectPath)

  loadAllPipelines: (projectPath) ->
    { host, project, repos } = @projects[projectPath]
    @fetch(host, "projects/#{project.id}/pipelines")
    .then( (pipelines) =>
      loads = []
      loads.push @loadPipelineJobs(host, project, pipeline) for pipeline in pipelines
      Promise.all(loads).then( ()=>
        return pipelines
      )
    )
    .then( (pipelines) =>
      @allPipelines[projectPath] = pipelines
      @view.onDataUpdate(null, @allPipelines)
      return pipelines
    )

  schedule: ->
    @timeout = setTimeout @update.bind(@), @period

  update: ->
    @pending = Object.keys(@projects).slice()
    @updatePipelines()

  updatePipeline: (pipeline, projectPath) ->
    { host, project, repos } = @projects[projectPath]
    @jobs[project.path_with_namespace] = null
    project.userForcedPipeline = pipeline
    @updateJobs(host, project, pipeline)

  updatePipelines: ->
    Object.keys(@projects).map(
      (projectPath) =>
        { host, project, repos } = @projects[projectPath]
        if project? and project.id? and not @updating[projectPath]
          @updating[projectPath] = true
          ref = project.userForcedPipeline?.ref || repos?.getShortHead?()
          if ref?
            log "project #{project} ref is #{ref}"
            ref = "?ref=#{ref}"
          else
            ref = ""
          if not @jobs[projectPath]?
            @view.loading(projectPath, "loading pipelines...")

          @fetch(host, "projects/#{project.id}/pipelines#{ref}").then(
            (pipelines) =>
              log "received pipelines from #{host}/#{project.id}", pipelines
              project.pipelines = pipelines;
              if pipelines.length > 0
                if project.userForcedPipeline
                  currentPipelineWrapped = pipelines.filter( (p) => p.id is project.userForcedPipeline.id)
                  # is in the pipelines?
                  if currentPipelineWrapped?.length > 0
                    currentPipeline = currentPipelineWrapped[0]
                if not currentPipeline
                  currentPipeline = pipelines[0]
                  project.userForcedPipeline = null
                @updateJobs(host, project, currentPipeline)
                @loadPipelineJobs(host, project, pipeline) for pipeline in pipelines
              else
                @onJobs(project, [])
          )
          .then( ()=>
            @loadAllPipelines(projectPath)
          )
          .catch((error) =>
            console.error "cannot fetch pipelines for project #{projectPath}", error
            @endUpdate(project)
          )
    )

  endUpdate: (project) ->
    log "project #{project} update end"
    @updating[project] = false
    @pending = @pending.filter((pending) => pending isnt project)
    if @pending.length is 0
      @schedule()
      @view.onDataUpdate(@jobs, @allPipelines)
      @activeSelector?.refresh()
    @jobs[project.path_with_namespace]

  updateJobs: (host, project, pipeline) ->
    if not @jobs[project.path_with_namespace]?
      @view.loading(project.path_with_namespace, "loading jobs...")
    @fetch(host, "projects/#{project.id}/" + "pipelines/#{pipeline.id}/jobs", true)
    .then((jobs) =>
      log "received jobs from #{host}/#{project.id}/#{pipeline.id}", jobs
      jobs.every (job) -> job.search = "id:#{job.id} name:#{job.name} runner:#{job.runner?.description} status:#{job.status}"
      if jobs.length is 0
        @onJobs(project, [
          name: pipeline.name
          pipeline: pipeline.id
          pipelineStatus: pipeline.status
          status: pipeline.status
          jobs: []
        ])
      else
        @onJobs(project, jobs.sort((a, b) -> a.id - b.id).reduce(
          (stages, job) ->
            stage = stages.find(
              (stage) -> stage.name is job.stage
            )
            if not stage?
              stage =
                name: job.stage
                pipeline: pipeline.id
                pipelineStatus: pipeline.status
                status: 'created'
                jobs: []
              stages = stages.concat([stage])
            stage.jobs = stage.jobs.concat([job])
            return stages
        , []).map((stage) ->
          Object.assign(stage, {
            firstFailedJob: stage.jobs
              .filter( (job) -> job.status is 'failed' )?[0]

            status: stage?.jobs
              .sort((a, b) -> b.id - a.id)
              .reduce((status, job) ->
                switch status
                  when 'failed' then 'failed'
                  when 'pending' then 'pending'
                  when 'manual' then 'manual'
                  when 'running' then 'running'
                  else job.status
              , 'created')
          })
        ))
    ).catch((error) =>
      console.error "cannot fetch jobs for pipeline ##{pipeline.id} of project #{project.path_with_namespace}", error
      @endUpdate(project)
    )

  alwaysFailed: (items)->
    passedNames = items.filter((job) => job.status is "success").map( (job)=> job.name)
    return items.filter((job) => job.status is "failed" and job.name not in passedNames)

  alwaysSuccess: (items)->
    failedNames = items.filter((job) => job.status is "failed").map( (job)=> job.name)
    return items.filter((job) => job.status is "success" and job.name not in failedNames)

  statistics: (jobs)->
    if jobs?.length
      total = jobs.filter ( (j) => j.status is 'success' or 'failed')

      alwaysSuccess = @alwaysSuccess( jobs )
      failed = jobs.filter ( (j) => j.status is 'failed')
      alwaysFailed = @alwaysFailed( jobs )
      unstable = failed.filter( (j) => j not in alwaysFailed)

      return {alwaysSuccess, unstable, alwaysFailed, total}
    else
      return {alwaysSuccess:[], unstable:[], alwaysFailed:[], total:[]}

  toHHMMSS: (sec_num) ->
    sec_num = Math.round(sec_num)
    hours = Math.floor(sec_num / 3600)
    minutes = Math.floor((sec_num - (hours * 3600)) / 60)
    seconds = sec_num - (hours * 3600) - (minutes * 60)
    if hours < 10
      hours = "0"+hours
    if minutes < 10
      minutes = "0"+minutes
    if seconds < 10
      seconds = "0"+seconds
    if hours is "00"
      "#{minutes}m #{seconds}s"
    else
      "#{hours}h #{minutes}m #{seconds}s"

  toType: (item, percentile) ->
    deviation = Math.round(item.duration / percentile * 100)
    if deviation < 85 then type = 'success'
    if deviation > 115 then type = 'warning'
    if deviation > 130 then type = 'error'
    return type

  loadPipelineJobs: (host, project, pipeline) ->
    @fetch(host, "projects/#{project.id}/" + "pipelines/#{pipeline.id}/jobs", true)
    .then((jobs) ->
      if jobs?.length > 0
        pipeline.commit = jobs[0].commit
        pipeline.created_at = jobs[0].created_at
        pipeline.finished_at = jobs[jobs?.length-1].finished_at
        pipeline.user = jobs[0].user
        pipeline.search = "id:#{pipeline.id} ref:#{pipeline.ref} sha:#{pipeline.commit?.short_id} status:#{pipeline.status}"
        pipeline.durationSuccess = jobs.filter( (j) -> j.status is 'success').reduce( ((max, j) ->
          Math.max(max, j.duration || 0)
        ), 0)
        pipeline.duration = jobs.reduce( ((max, j) ->
          Math.max(max, j.duration || 0)
        ), 0)
      pipeline.loadedJobs = jobs
    )
    .catch((error) =>
      console.error "cannot fetch jobs for pipeline ##{pipeline.id} of project #{project.path_with_namespace}", error
    )

  onJobs: (project, stages) ->
    @jobs[project.path_with_namespace] = stages.slice()
    @endUpdate(project.path_with_namespace)
    Promise.resolve(stages)

  stop: ->
    if @timeout?
      clearTimeout @timeout
    if @watchTimeout?
      clearTimeout @watchTimeout
    @view.hide()

  deactivate: ->
    @stop()

module.exports = GitlabStatus
