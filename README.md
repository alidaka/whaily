# Whaily

## Local execution
### Setup
```
# install and setup dependencies
> mix setup

# set up environment variables
> cp .envrc.example .envrc
> vim envrc #...
> direnv allow
```

### Run
```
# run locally
> mix phx.server

# or, debug locally
> iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000)

## Deployment
```
flyctl deploy
```

Set secrets via `fly secrets set FOO=bar`

Visit [whaily.lidaka.io](https://whaily.lidaka.io) (or [whaily.fly.dev](https://whaily.fly.dev))

## Meta thoughts at SHA `d969b73`
This commit is the first full vertical slice of value:
* Backend gets a meaningful piece of data
* Frontend loads, receives that data, and shows it
* Deploys to a live site

This took about 5.5 hours, ~half of which was spent learning Phoenix: setting up esbuild/asset pipeline after not doing so OOB, then learning how to parse json.

Next up:
* Add more useful/fun data
    * Election data?
* Improve presentation
* Improve operations
    * Set up logging, observability

# Attribution
Thank you to:
* Google Calendar for Chuck's Hop Shop data
* [Open-Meteo](https://open-meteo.com/) for weather data
