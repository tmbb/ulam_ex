#![allow(non_snake_case)]

use nuts_rs::{CpuMath, CpuLogpFunc, LogpError, DiagGradNutsSettings, Settings, Chain};
use rand;
use thiserror::Error;
use std::vec::Vec;

use crate::autograd;
use crate::autograd::Gradient;
<% cached_summations = Enum.sort(@model.cache.summations) %>
#[derive(Debug, Clone)]
pub struct CacheContainer {<%= for {{_rfrac, {variable_name, _}}, last?} <- with_is_last(cached_summations) do %>
    <%= variable_name %>: f64<%= if not last? do %>,<% end %><% end %>
}

impl CacheContainer {
    pub fn from_data(data: &DataContainer) -> CacheContainer {
        // Some of the data parameters might be unused in caching,
        // but that is not easy to determine without some sophisticated analysis.
        // We just tell rust not to warn us if anything is missing.
        //
        // Why do we define variables for all data variables?
        // It's simply to make it easier to define the expressions inside the cache.
        <%= for data <- @model.data do %>
        #[allow(unused)]
        let <%= data.name %> = &data.<%= data.name %>;
        <% end %>

        // Evaluate the cached sums with indices instead of the more idiomatic
        // idioms such as zipping iterators together, because this way
        // things are much more similar to how they are defined on the Elixir side.
        CacheContainer{<%=
            for {{rfrac, {variable_name, {index, limit}}}, last?} <- with_is_last(cached_summations) do %>
            <%= variable_name %>: (0..(*<%= Compiler.to_rust_plain_vars(limit) %> as usize))
                .into_iter()
                .map(|<%= Compiler.to_rust(index) %>| { <%= Compiler.to_rust_plain_vars(rfrac) %> })
                .sum()<%= if not last? do %>,
<% end %><% end %>
        }
    }
}

#[derive(Debug, Clone)]
pub struct DataContainer {<%= for {data, last?} <- with_is_last(@model.data) do %>
    <%= data.rust_name %>: <%= data.rust_type %><%= if not last? do %>,<% end %><% end %>
}

// Define a function that computes the unnormalized posterior density
// and its gradient.
#[derive(Debug)]
pub struct <%= @model.name %>PosteriorDensity {
    cache: CacheContainer,
    data: DataContainer
}

// The density might fail in a recoverable or non-recoverable manner...
#[derive(Debug, Error)]
pub enum PosteriorLogpError {}

impl LogpError for PosteriorLogpError {
    fn is_recoverable(&self) -> bool {
        false
    }
}

impl CpuLogpFunc for <%= @model.name %>PosteriorDensity {
    type LogpError = PosteriorLogpError;

    fn dim(&self) -> usize { <%= @model.parameter_space_dimensions %> }

    fn logp(&mut self, position: &[f64], grad: &mut [f64]) -> Result<f64, Self::LogpError> {
        let <%= @model.tape_name %> = autograd::Tape::new();
        // Define the target as the first node of the tape and
        // initialize its value to zero.
        let target = <%= @model.tape_name %>.add_var(0.0);
        
        // Define the parameters as nodes in the tape,
        // so that we can easily get their gradients
        <%= for parameter <- @model.parameters do
        %>let <%= parameter.name %> = <%= @model.tape_name %>.add_var(position[<%= parameter.location %>]);
        <% end %>

        let target = target + (
            - 2.0 * (self.data.n as f64) * epsilon.ln() * epsilon * epsilon
            - (self.data.n as f64) * alpha * alpha
            - 2.0 * alpha * beta * self.cache.sum_of_self_data_x_i__0
            + 2.0 * alpha * self.cache.sum_of_self_data_y_i__3
            - beta * beta * self.cache.sum_of_self_data_x_i_times_self_data_x_i__1
            + 2.0 * beta * self.cache.sum_of_self_data_x_i_times_self_data_y_i__2
            - self.cache.sum_of_self_data_y_i_times_self_data_y_i__4
          ) / ((2.0 * epsilon * epsilon));


        let target_grad = target
            .grad()
            .wrt(&[<%= for {parameter, last?} <- with_is_last(@model.parameters) do %>
                <%= parameter.name %><%= if not last? do %>,<% end %><% end %>
            ]);

        for i in 0..(<%= @model.parameter_space_dimensions %>) {
            grad[i] = target_grad[i];
        }

        return Ok(target.val)
    }
}

pub fn fit_with_default_settings(data_container: DataContainer) -> Vec<Vec<f64>> {
    // If none are given, we get the default sampler arguments
    let mut settings = DiagGradNutsSettings::default();
    // and modify as we like
    settings.num_tune = 1000;
    settings.maxdepth = 30;

    fit(data_container, settings)
}

pub fn fit(data_container: DataContainer, mut settings: DiagGradNutsSettings) -> Vec<Vec<f64>> {
    let cache_container = CacheContainer::from_data(&data_container);
        
    // We instanciate our posterior density function
    let logp_func = <%= @model.name %>PosteriorDensity{
        data: data_container,
        cache: cache_container
    };

    let math = CpuMath::new(logp_func);
    
    let n_params = 3;
    let n_iterations = 2000;

    let mut rng = rand::thread_rng();
    let mut sampler = settings.new_chain(0, math, &mut rng);
    
    // Set to some initial position and start drawing samples.
    sampler.set_position(&vec![0.01f64; n_params]).expect("Unrecoverable error during init");
    let mut trace = vec![];  // Collection of all draws

    for _i in 1..n_iterations {
        let (draw, _info) = sampler.draw().expect("Unrecoverable error during sampling");
        trace.push(draw.to_vec());
    }

    trace
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn autograd_works() {
        let data_x = vec![
            -1.718, 1.162, 3.234, -0.832, -0.038, 0.073, -0.412,
            -2.056, -0.208, 1.276, 1.492, 0.993, 0.562, -2.973,
            -1.997, -1.312, -2.520, -0.222, 3.455, -0.305, 1.691,
            -1.332, -1.070, 0.211, 0.597, 0.858, 0.621, -1.479,
            0.202, 1.519
        ];

        let data_y = vec![
            0.938, 3.286, 5.149, 1.713, 2.112, 2.895, 2.463,
            1.200, 2.591, 3.652, 3.921, 3.649, 3.589, 0.096,
            1.089, 1.303, 0.714, 2.027, 5.471, 2.740, 4.187,
            1.536, 1.365, 2.635, 2.608, 3.076, 3.184, 1.195,
            2.844, 4.306
        ];

        let data_container = DataContainer{
            x: data_x,
            y: data_y,
            n: 30
        };

        fit_with_default_setting(data_container);

        ()
    }
}