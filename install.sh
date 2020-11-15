#!/bin/sh

export AWS_REGION=us-east-2
export CLUSTER_NAME=Ohio
export ACM_ARN='arn:aws:acm:us-east-2:xxx:certificate/xxx'

apply_subst() {
    cat "$1" | envsubst > .apply.yml
    kubectl apply -f .apply.yml
    rm .apply.yml
}


## https://aws.amazon.com/blogs/containers/using-alb-ingress-controller-with-amazon-eks-on-fargate/

# eksctl delete cluster --region=us-east-2 --name=Ohio
eksctl create cluster --name $CLUSTER_NAME --region $AWS_REGION --fargate

sleep 60

## https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.0/guide/controller/installation/
eksctl utils associate-iam-oidc-provider \
    --region $AWS_REGION \
    --cluster $CLUSTER_NAME \
    --approve

# curl -Lo iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v2.0.1/docs/install/iam_policy.json


aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json

## https://aws.amazon.com/blogs/containers/using-alb-ingress-controller-with-amazon-eks-on-fargate/
export STACK_NAME=eksctl-$CLUSTER_NAME-cluster
export VPC_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" | jq -r '[.Stacks[0].Outputs[] | {key: .OutputKey, value: .OutputValue}] | from_entries' | jq -r '.VPC')
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.Account')

## https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.0/guide/controller/installation/
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --approve

cd kube_configs
cd cert
kubectl -n kube-system create secret generic aws-load-balancer-webhook-tls \
  --from-file=./tls.crt \
  --from-file=./tls.key
cd ..

# curl -Lo alb-controller.yml https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/main/docs/install/v2_0_1_full.yaml
apply_subst alb-controller.yml
kubectl apply -f nginx.yaml
apply_subst nginx-ingress.yaml
cd ..




# openssl req -x509 -newkey rsa:4096 -sha256 -days 36500 -nodes \
#   -keyout tls.key -out tls.crt -subj "/CN=aws-load-balancer-webhook-service.kube-system.svc" \
#   -addext "subjectAltName=DNS:aws-load-balancer-webhook-service.kube-system.svc,DNS:aws-load-balancer-webhook-service.kube-system.svc.cluster.local"