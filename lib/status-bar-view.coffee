{CompositeDisposable} = require('atom')
log = require './log'

class StatusBarView extends HTMLElement
    init: ->
        @classList.add('status-bar-gitlab', 'inline-block')
        @activate()
        @currentProject = null
        @stages = {}
        @pipelines = {}
        @statuses = {}
        @tooltips = []
        @controller = null

    setController: (controller) =>
      @controller = controller

    activate: => @displayed = false
    deactivate: =>
        @disposeTooltips()
        @dispose() if @displayed

    onDisplay: (@display) ->
        if @displayed
            @display(@)

    onDispose: (@dispose) ->

    hide: =>
        @dispose() if @displayed
        @displayed = false

    show: =>
        if @display?
            @display(@) if not @displayed
        @displayed = true

    onProjectChange: (project) =>
        log "current project becomes #{project}"
        @currentProject = project
        if project?
            if @stages[project]? or @pipelines[project]?
                @update(project, @stages[project], @pipelines[project])
            else if @statuses[project]?
                @loading(project, @statuses[project])
            else
                @unknown(project)

    onDataUpdate: (stages, pipelines) =>
        log "new data", stages
        if stages
          @stages = stages
        if pipelines
          @pipelines = pipelines
        @update(@currentProject, @stages[@currentProject], @pipelines[@currentProject])

    disposeTooltips: =>
        @tooltips.forEach((tooltip) => tooltip.dispose())
        @tooltips = []

    loading: (project, message) =>
        log "project #{project} loading with status '#{message}'"
        @statuses[project] = message
        if @currentProject is project
            @show()
            @disposeTooltips()
            status = document.createElement('div')
            status.classList.add('inline-block')
            icon = document.createElement('a')
            icon.classList.add('icon', 'icon-gitlab')
            icon.onclick =  (e) =>
                @controller.openGitlabCICD(project);
            @tooltips.push atom.tooltips.add icon, {
                title: "GitLab project #{project}"
            }
            span = document.createElement('span')
            span.classList.add('icon', 'icon-sync', 'icon-loading')
            @tooltips.push atom.tooltips.add(span, {
                title: message,
            })
            status.appendChild icon
            status.appendChild span
            @setchild(status)

    setchild: (child) =>
        if @children.length > 0
            @replaceChild child, @children[0]
        else
            @appendChild child

    update: (project, stages, pipelines) =>
        log "updating stages of project #{project} with", stages
        @show()
        @disposeTooltips()
        status = document.createElement('div')
        status.classList.add('inline-block')
        # workaround, the passed data needs to be refactored
        # pass pipeline instead of hacked stages
        if stages?.length > 0
          firstStage = stages[0]
          if firstStage.jobs?.length > 0
            firstJob = firstStage.jobs[0]

        if pipelines?.length > 0

          allPipeline = document.createElement('span')
          allPipeline.classList.add('icon', 'icon-inbox')
          @tooltips.push atom.tooltips.add allPipeline, {
            title: "Open all pipeline selector"
          }
          allPipeline.onclick = (e) =>
            @controller.openAllPipelineSelector(project);
          status.appendChild allPipeline

          first3pipelines = pipelines[..3]
          first3pipelines.forEach((pipeline) =>
              pipe = document.createElement('a')
              pipe.classList.add('icon', "gitlab-#{pipeline.status}")
              if firstStage?.pipeline is pipeline.id
                pipe.innerHTML = "*&nbsp;"
              pipe.onclick =  (e) =>
                @controller.updatePipeline(pipeline, project);
              @tooltips.push atom.tooltips.add pipe, {
                  title: "##{pipeline.id} | #{pipeline.ref} | #{pipeline.commit?.title}"
              }
              status.appendChild pipe
          )

        icon = document.createElement('a')
        icon.classList.add('icon', 'icon-gitlab')
        icon.onclick =  (e) =>
            @controller.openGitlabCICD(project);
        @tooltips.push atom.tooltips.add icon, {
            title: "GitLab project #{project} #{firstStage?.pipeline} on branch #{firstJob?.ref}"
        }
        status.appendChild icon
        if stages.length is 0
            e = document.createElement('span')
            e.classList.add('icon', 'icon-question')
            @tooltips.push atom.tooltips.add e, {
                title: "no pipeline found"
            }
            status.appendChild e
        else
            icon.onclick =  (e) =>
                @controller.openPipeline(project, stages);

            pipeline = document.createElement('span')
            pipeline.classList.add('icon', "gitlab-#{firstStage?.pipelineStatus}")
            pipeline.innerHTML = "=&nbsp;"
            pipeline.onclick = (e) =>
              @controller.openPipelineSelector(project);
            @tooltips.push atom.tooltips.add pipeline, {
                title: "#{firstJob?.commit?.title} | #{firstStage?.pipeline}"
            }
            status.appendChild pipeline

            stages.forEach((stage) =>
                failedJobs =  stage.jobs.filter( (job) ->  job.status is 'failed' )
                runningJobs =  stage.jobs.filter( (job) ->  job.status is 'running' )

                e = document.createElement('a')
                e.classList.add('icon', "gitlab-#{stage.status}")
                e.onclick =  (e) =>
                  @controller.openJobSelector(project, stage);
                @tooltips.push atom.tooltips.add e, {
                    title: "#{stage.name}: #{stage.status} | #{failedJobs.length} failed jobs out of #{stage.jobs.length} | Click to individually select a job's log to download."
                }
                status.appendChild e

                if failedJobs.length > 0
                  e = document.createElement('a')
                  e.classList.add('icon', 'icon-cloud-download', 'text-error')
                  e.onclick =  (e) =>
                      @controller.openLogs(project, failedJobs);
                  @tooltips.push atom.tooltips.add e, {
                      title: "Download all failed logs (#{failedJobs.length}) from the stage #{stage.name}"
                  }
                  status.appendChild e

                if runningJobs.length > 0
                  e = document.createElement('a')
                  e.classList.add('icon', 'icon-cloud-download', 'text-info')
                  e.onclick =  (e) =>
                      @controller.openLogs(project, runningJobs);
                  @tooltips.push atom.tooltips.add e, {
                      title: "Download all running logs (#{runningJobs.length}) from the stage #{stage.name}"
                  }
                  status.appendChild e

                if stage.jobs.length > 0 and stage.name is 'test'
                  e = document.createElement('a')
                  e.classList.add('icon', 'icon-cloud-download', 'text-subtle')
                  e.onclick =  (e) =>
                      @controller.openLogs(project, stage.jobs);
                  @tooltips.push atom.tooltips.add e, {
                      title: "Download all logs (#{stage.jobs.length}) from the stage #{stage.name}"
                  }
                  status.appendChild e
            )
        @setchild(status)

    unknown: (project) =>
        log "project #{project} is unknown"
        @statuses[project] = undefined
        if @currentProject is project
            @show()
            @disposeTooltips()
            status = document.createElement('div')
            status.classList.add('inline-block')
            span = document.createElement('span')
            span.classList.add('icon', 'icon-question')
            status.appendChild span
            @tooltips.push atom.tooltips.add(span, {
                title: "no GitLab project detected in #{project}"
            })
            @setchild(status)

module.exports = document.registerElement 'status-bar-gitlab',
    prototype: StatusBarView.prototype, extends: 'div'
