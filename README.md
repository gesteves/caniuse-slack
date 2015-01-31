# caniuse-slack

A standalone Slack integration that allows you to request and see [caniuse.com](http://caniuse.com) data in your Slack channels.

![](http://i.imgur.com/p7kvKFI.png)

## Requirements

You'll need a [Slack](https://slack.com) account, obviously, and a free [Heroku](https://www.heroku.com/) account to host the bot. You'll also need to be able to set up new integrations in Slack; if you're not able to do this, contact someone with admin access in your organization.

## Installation

1. Set up a Slack outgoing webhook at https://slack.com/services/new/outgoing-webhook. Make sure to pick a trigger word, such as `caniuse`. Copy the outgoing webhook's token, you'll need it later.

2. Set up a Slack incoming webhook at https://slack.com/services/new/incoming-webhook. Copy the URL for the incoming webhook, you'll also need it later.

3. Click this button to set up your Heroku app: [![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)   
If you'd rather do it manually, then just clone this repo, set up a Heroku app with Redis Cloud (the free level is more than enough for this), and deploy thie app there. Make sure to set up the config variables in
[.env.example](https://github.com/gesteves/caniuse-slack/blob/master/.env.example) in your Heroku app's settings screen.

5. Point the outgoing webhook to https://[YOUR-HEROKU-APP].herokuapp.com

## Usage

* `caniuse FEATURE`: Shows the caniuse data for said FEATURE, e.g. `caniuse flexbox`.

## Credits & acknowledgements

Big thanks to [Alex Wolkov](http://alexw.me/) for letting me take a look at his [Hubot caniuse integration](https://github.com/altryne/hubot-caniuse), which was the inspiration for this. Also, big thanks to [Alexis Deveria](https://twitter.com/Fyrd), because caniuse.com is awesome.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

Feel free to open a new issue if you have questions, concerns, bugs, or feature requests. Just remember that I'm doing this for fun, for free, in my free time, and I may not be able to help you, respond in a timely manner, or implement any feature requests.

## License 

Copyright (c) 2015, Guillermo Esteves
All rights reserved.

BSD license

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
