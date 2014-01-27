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

    constructor: (@name, @code)->

    run: (casper)->
        throw "Not implemented"



class CheckOperation extends Operation

    run: (casper)->
        check = casper.evaluate @code
        if not check
            console.error @name, ": failed, dying."
            casper.die()


class WaitOperation extends Operation

    constructor: (@name, @options)->

    run: (casper)->
        condition = @options.condition
        if condition?
            casper.waitFor -> casper.evaluate condition, (-> console.log "WAITED"), (-> console.log "TIMEOOUT"), @options.timeout
        else
            casper.wait @options.timeout

class ActionOperation extends Operation
    
    run: (casper)->
        @code.apply casper



class DebugOperation extends Operation
    
    run: (casper)->
        console.log "DEBUG ", casper.evaluate @code



class ScreenshotOperation extends Operation

    constructor: (@name, @options)->
    
    run: (casper, writer)->
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


OPERATION_MAP =
    check: CheckOperation
    action: ActionOperation
    screenshot: ScreenshotOperation
    debug: DebugOperation
    wait: WaitOperation

operation_from_label = (opname)->
    for opprefix,opclass of OPERATION_MAP
        if opname.indexOf(opprefix) == 0
            return opclass
    undefined


class Step

    constructor: (@text, @code)->

    operations: ->
        operations = []
        for k,v of @code
            console.log k
            operation = new (operation_from_label k)(k,v)
            operations.push operation
        operations

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
                        console.log step.name
                        writer.append step.text
                for op_id, operation of step.operations()
                    do (step_id, op_id, operation) ->
                        casper.then ->
                            operation.run this, writer
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
        for stepData in brocco.parse "dummy.litcoffee", body
            steps.push new Step stepData.docsText, cs.eval(stepData.codeText)
        new Tutorial config, steps

if casper.cli.args.length != 1
    console.log "Expecting step markdown file as argument."
    casper.exit();
else
    filepath = casper.cli.args[0]
    Tutorial.from_file(filepath).start()
