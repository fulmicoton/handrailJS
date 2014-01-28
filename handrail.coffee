#!/usr/bin/env casperjs

brocco = require './vendor/brocco'
fs = require 'fs'
cs = require('./vendor/coffee-script.js').CoffeeScript

CASPER_CONFIG = 
    #clientScripts:  [ 'vendor/jquery-1.11.0.min.js' ]
    logLevel: "info"
    verbose: true    
casper = require('casper').create CASPER_CONFIG

split_data = (data)-> 
    limit = data.indexOf "---"
    header = data[...limit]
    body = data[limit+3...]
    [ header, body ]

casper.on 'http.status', (resource)->
    console.log 'status ON ' + resource, resource.url

casper.on 'http.status.400', (resource)->
    console.log '400 ON ' + resource.url

casper.on 'http.status.404', (resource)->
    console.log '404 ON ' + resource.url

casper.on 'remote.message', (resource)->
    console.log 'REMOTE LOG ' + resource



class Operation

    constructor: (@name, @options)->

    run: (casper)->
        throw "Not implemented"

    setup: (casper, writer)->
        casper.then =>
            console.log " -", @name
            @run casper, writer

class CheckOperation extends Operation

    run: (casper)->
        check = casper.evaluate @code
        if not check
            console.error @name, ": failed, dying."
            casper.die()

class WaitOperation extends Operation

    run: (casper)->
        condition = @options.condition
        timeout = @options.timeout ? 5000
        args = @options.args
        if condition?
            casper.waitFor (-> casper.evaluate condition, args...), (-> console.log "WAITED"), (-> console.log "TIMEOOUT"), timeout
        else
            casper.wait timeout

class ActionOperation extends Operation
    
    run: (casper)->
        @options.apply casper


class ClickOperation extends Operation

    constructor: (@name, @options)->
        @subops = []
        timeout = @options.timeout ? 5000
        if @options.selector
            @subops.push new WaitOperation @name + "_wait",
                condition: (selector) -> $(selector).length >= 1
                args: [ @options.selector ]
                timeout: timeout
            selector = @options.selector
            @subops.push new ActionOperation @name+"_action", ->
                @click selector
        else if @options.label?
            tag = @options.tag
            label = @options.label
            args = [ label ]
            if tag?
                args.push tag
            @subops.push new WaitOperation @name + "_wait",
                condition: (label, tag)-> 
                    selector = (tag ? "*") ":contains(#{label})"
                    console.log "SELECTOR", JSON.stringify selector
                    $(selector).length >= 1
                "args": args
            @subops.push new ActionOperation @name+"_action", ->
                if tag?
                    @clickLabel label, tag
                else
                    @clickLabel label

        else
            throw "Cannot build click operation with " + JSON.stringify @options

    setup: (casper, writer)->
        for op in @subops
            do (op)->
                casper.then ->
                    console.log " -", op.name
                    op.run casper, writer


class DebugOperation extends Operation
    
    run: (casper)->
        console.log "DEBUG(#{@name}) :", casper.evaluate @options

class ScreenshotOperation extends Operation
    
    run: (casper, writer)->
        if not @options.filepath?
            @options.filepath = @name + ".png"
        if not @options.box? and @options.selector
            selector = @options.selector
            get_box = (selector)->
                $el = $(selector)
                box = $el.offset()
                box.width = $el.outerWidth()
                box.height = $el.outerHeight()
                box
            @box = casper.evaluate get_box, @options.selector
        casper.capture @options.filepath, @box
        writer.append "<img src='#{@options.filepath}'>"

operation_from_label = (opname)->
    for opprefix,opclass of OPERATION_MAP
        if opname.indexOf(opprefix) == 0
            return opclass
    undefined

class Step

    constructor: (@text)-> 
        @operations = []

    add_operation: (operation)->
        console.log "Adding operation", operation.name
        @operations.push operation

class Writer

    constructor: (@filepath)->
        @data = []

    append: (part)->
        @data.push part

    write: ->
        if @filepath?
            fs.write @filepath, @data.join '\n', 'w'


class Tutorial
    
    constructor: (@config, @steps)->

    start: ->
        writer = new Writer @config.output
        steps_data = []
        casper.start @config.url, =>
            casper.viewport @config.width, @config.height
            for step_id, step of @steps
                do (step) ->
                    casper.then ->
                        casper.log "Step " + step_id, 'info'
                        writer.append step.text
                for operation in step.operations
                    operation.setup casper, writer
            casper.then ->
                writer.write()
        casper.run()

    @from_file: (filepath, cb)->
        # parse file in filepath into a tutorial object.
        data = fs.read filepath 
        [ header, body ] = split_data data
        config = cs.eval header
        steps = []
        # just a dummy name to make docco thinks its a litterate coffeescript file.
        new_step = null
        step_id = 1
        operation_appender = (name, optype)->
            global[name] = (params) ->
                op_name = params.name
                if not op_name? or op_name.length==0
                    op_name = name + "_" + step_id + "_" + (new_step.operations.length + 1)
                new_step.add_operation (new optype op_name, params)
            step_id += 1
        operation_appender "check", CheckOperation
        operation_appender "action", ActionOperation
        operation_appender "screenshot", ScreenshotOperation
        operation_appender "debug", DebugOperation
        operation_appender "wait", WaitOperation
        operation_appender "click", ClickOperation
        for stepData in brocco.parse "dummy.litcoffee", body
            new_step = new Step stepData.docsText
            if stepData.codeText?
                cs.eval stepData.codeText
            steps.push new_step
        new Tutorial config, steps

if casper.cli.args.length != 1

    console.log "Expecting step markdown file as argument."
    casper.exit();
else
    filepath = casper.cli.args[0]
    Tutorial.from_file(filepath).start()
