data {
  int<lower=0> n;
  vector[n] x;
  vector[n] y;
}

parameters {
  real intercept;
  real slope;
  real<lower=0> error;
  real mu_x;
  real<lower=0> sigma_x;
}

model {
  x ~ normal(mu_x, sigma_x);
  y ~ normal(((x * slope) + intercept), error);
}
