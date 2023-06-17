FROM alpine:3.18.2 as builder

RUN apk add nim
RUN apk add nimble
RUN apk add git
RUN apk add build-base

WORKDIR /faketls

COPY config.nims config.nims
RUN nim install

COPY libs libs
COPY src src
COPY .gitignore .gitignore
RUN nim build

FROM alpine:3.18.2 as runner

WORKDIR /faketls 

COPY --from=builder /faketls/dist/FTT ./FTT
RUN chmod +x FTT

ENTRYPOINT ["./FTT"]