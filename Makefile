IMAGE ?= brs-swarm-explorer
TAG   ?= dev

.PHONY: build run save clean

# Build the production image. CI builds the same thing with
# --platform linux/amd64 and publishes the tarball; nothing is pushed to a
# registry and no release is created.
build:
	docker build --platform linux/amd64 -t $(IMAGE):$(TAG) .

run:
	docker run --rm -p 4000:4000 --env-file .env $(IMAGE):$(TAG)

# The artifact workstream F loads with: gunzip -c <file> | docker load
save: build
	docker save $(IMAGE):$(TAG) | gzip -9 > swarm-explorer-$(TAG).tar.gz
	sha256sum swarm-explorer-$(TAG).tar.gz > SHA256SUMS

clean:
	-docker rmi $(IMAGE):$(TAG)
