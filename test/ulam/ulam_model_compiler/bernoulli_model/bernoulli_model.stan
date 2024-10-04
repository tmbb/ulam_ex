data {
  int<lower=0> n;
  array[n] int<lower=0, upper=1> y;
}

parameters {
  real<lower=0, upper=1> theta;
}

model {
  theta ~ beta(1, 1);
  y ~ bernoulli(theta);
}
