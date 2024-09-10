# Whaily

## Local execution
```
# install and setup dependencies
> mix setup

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

Visit [whaily.fly.dev](whaily.fly.dev)

## Meta thoughts at SHA `d969b73`
This commit is the first full vertical slice of value:
* Backend gets a meaningful piece of data
* Frontend loads, receives that data, and shows it
* Deploys to a live site

This took about 5.5 hours, ~half of which was spent learning Phoenix: setting up esbuild/asset pipeline after not doing so OOB, then learning how to parse json.

Next up:
* Add more useful/fun data
    * Weather data
    * Election data?
* Improve presentation
    * Fine tune food truck today vs tomorrow presentation
    * Make more visual separation, styling, ...
* Improve operations
    * `fly launch` included a Github Action - needs auth
    * Set up logging, observability
    * Use my own domain

# Attribution
Thank you to:
* Google Calendar for Chuck's Hop Shop data
* [Open-Meteo](https://open-meteo.com/) for weather data
